import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { HttpClient } from '../network/HttpClient';
import { CfClearanceRefreshService } from '../network/CfClearanceRefreshService';
import { MessageBusService } from './MessageBusService';
import { PreferencesUtil } from '../storage/PreferencesUtil';
import { AuthSessionService } from '../auth/AuthSessionService';

const TAG: string = 'PreloadedDataService';
const PRELOAD_PATH: string = '/latest';
const PREF_KEY_LONG_POLLING_BASE_URL: string = 'message_bus_long_polling_base_url_v1';
const PREF_KEY_SHARED_SESSION_KEY: string = 'message_bus_shared_session_key_v1';
const PREF_KEY_CDN_URL: string = 'site_cdn_url_v1';
const PREF_KEY_S3_CDN_URL: string = 'site_s3_cdn_url_v1';
const PREF_KEY_S3_BASE_URL: string = 'site_s3_base_url_v1';
const PREF_KEY_ENABLED_REACTIONS: string = 'site_enabled_reactions_v1';
const LEGACY_ENABLED_REACTIONS: string[] = ['heart', '+1', 'laughing', 'open_mouth', 'clap'];
const DEFAULT_ENABLED_REACTIONS: string[] = [
  'heart',
  '+1',
  'laughing',
  'open_mouth',
  'clap',
  'confetti_ball',
  'hugs',
  'distorted_face',
  'tieba_087',
  'bili_057'
];

/**
 * 预加载数据服务
 *
 * 从 Discourse HTML 的 data-preloaded 属性中提取：
 * - siteSettings.long_polling_base_url（MessageBus 独立域名）
 * - topicTrackingStateMeta（各频道初始 message_id）
 * - topicTrackingStates（话题追踪状态，用于 new/unread 计数）
 * - meta.shared_session_key（跨域长轮询认证）
 */
export class PreloadedDataService {
  private static instance: PreloadedDataService | null = null;

  private loaded: boolean = false;
  private inFlight: Promise<void> | null = null;
  private configLoaded: boolean = false;
  private configInFlight: Promise<void> | null = null;
  private configuredFromCache: boolean = false;

  private longPollingBaseUrl: string | null = null;
  private sharedSessionKey: string | null = null;
  private cdnUrl: string | null = null;
  private s3CdnUrl: string | null = null;
  private s3BaseUrl: string | null = null;
  private topicTrackingStateMeta: Map<string, number> | null = null;
  private topicTrackingStates: Record<string, Object>[] | null = null;
  private enabledReactions: string[] | null = null;

  private constructor() {
  }

  static getInstance(): PreloadedDataService {
    if (PreloadedDataService.instance === null) {
      PreloadedDataService.instance = new PreloadedDataService();
    }
    return PreloadedDataService.instance;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  /**
   * 从 /site.json 的 client_settings 提取到 long_polling_base_url 时调用（绕开 CF HTML challenge）
   */
  setLongPollingBaseUrlFromApi(baseUrl: string): void {
    const normalized: string | null = this.normalizePollingBaseUrl(baseUrl);
    if (normalized === null) return;
    if (normalized === this.longPollingBaseUrl) return;
    this.longPollingBaseUrl = normalized;
    try {
      MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
    } catch (_) {
    }
    // 缓存到 Preferences 供下次启动使用
    PreferencesUtil.putString(PREF_KEY_LONG_POLLING_BASE_URL, normalized).catch((_: Object) => {});
    if (AppConstants.DEBUG_TRACKING) {
      hilog.info(0x0000, TAG, 'longPollingBaseUrl set from site.json api: %{public}s', normalized);
    }
  }

  getLongPollingBaseUrl(): string | null {
    return this.longPollingBaseUrl;
  }

  getSharedSessionKey(): string | null {
    return this.sharedSessionKey;
  }

  getCdnUrl(): string | null {
    return this.cdnUrl;
  }

  getS3CdnUrl(): string | null {
    return this.s3CdnUrl;
  }

  getS3BaseUrl(): string | null {
    return this.s3BaseUrl;
  }

  getTopicTrackingStateMeta(): Map<string, number> | null {
    return this.topicTrackingStateMeta;
  }

  getTopicTrackingStates(): Record<string, Object>[] | null {
    return this.topicTrackingStates;
  }

  getEnabledReactions(): string[] {
    const source: string[] | null = this.enabledReactions;
    if (source === null || source.length === 0) {
      return this.cloneEnabledReactions(DEFAULT_ENABLED_REACTIONS);
    }
    if (this.isLegacyEnabledReactions(source)) {
      return this.cloneEnabledReactions(DEFAULT_ENABLED_REACTIONS);
    }
    return this.cloneEnabledReactions(source);
  }

  async clearSessionScopedState(): Promise<void> {
    this.loaded = false;
    this.inFlight = null;
    this.configLoaded = false;
    this.configInFlight = null;
    this.configuredFromCache = false;
    this.sharedSessionKey = null;
    this.topicTrackingStateMeta = null;
    this.topicTrackingStates = null;
    this.enabledReactions = null;

    try {
      MessageBusService.getInstance().configure(this.longPollingBaseUrl, null);
    } catch (_) {
    }

    try {
      await PreferencesUtil.ensureInit();
      await PreferencesUtil.delete(PREF_KEY_SHARED_SESSION_KEY);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Clear sharedSessionKey cache failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 仅加载 MessageBus 配置（避免解析 data-preloaded 大 JSON 导致 UI/消息处理卡顿）：
   * - meta.shared_session_key
   * - siteSettings.long_polling_base_url
   *
   * 启动策略：先从 Preferences 读取缓存并 configure()，再后台抓一次 HTML 刷新；若值变化则重新 configure() 触发轮询重启。
   */
  async ensureConfigLoaded(silent: boolean = false): Promise<void> {
    await this.configureBusFromCacheIfNeeded();
    if (this.loaded) {
      this.configLoaded = true;
      try {
        MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
      } catch (_) {
      }
      return;
    }
    if (this.configLoaded) return;
    if (this.configInFlight !== null) {
      return await this.configInFlight;
    }
    this.configInFlight = this.loadConfigOnly(silent);
    try {
      await this.configInFlight;
    } finally {
      this.configInFlight = null;
    }
  }

  async ensureLoaded(silent: boolean = false): Promise<void> {
    if (this.loaded) return;
    if (this.inFlight !== null) {
      return await this.inFlight;
    }
    this.inFlight = this.load(silent);
    try {
      await this.inFlight;
    } finally {
      this.inFlight = null;
    }
  }

  async refresh(silent: boolean = false): Promise<void> {
    this.reset();
    await this.ensureLoaded(silent);
  }

  reset(): void {
    this.loaded = false;
    this.longPollingBaseUrl = null;
    this.sharedSessionKey = null;
    this.cdnUrl = null;
    this.s3CdnUrl = null;
    this.s3BaseUrl = null;
    this.topicTrackingStateMeta = null;
    this.topicTrackingStates = null;
    this.enabledReactions = null;
    this.inFlight = null;
    this.configLoaded = false;
    this.configInFlight = null;
    this.configuredFromCache = false;
  }

  private captureAuthGeneration(): number {
    return AuthSessionService.getInstance().captureGeneration();
  }

  private isAuthGenerationCurrent(authGeneration: number, stage: string): boolean {
    const authSession: AuthSessionService = AuthSessionService.getInstance();
    if (authSession.isCurrentGeneration(authGeneration)) {
      return true;
    }
    hilog.info(
      0x0000,
      TAG,
      'Skip stale preloaded result stage=%{public}s authGeneration=%{public}d currentGeneration=%{public}d',
      stage,
      authGeneration,
      authSession.getGeneration()
    );
    return false;
  }

  private async configureBusFromCacheIfNeeded(): Promise<void> {
    if (this.configuredFromCache) return;
    this.configuredFromCache = true;
    const authGeneration: number = this.captureAuthGeneration();

    try {
      await PreferencesUtil.ensureInit();
      const cachedBaseRaw: string = await PreferencesUtil.getString(PREF_KEY_LONG_POLLING_BASE_URL, '');
      const cachedKeyRaw: string = await PreferencesUtil.getString(PREF_KEY_SHARED_SESSION_KEY, '');
      const cachedCdnRaw: string = await PreferencesUtil.getString(PREF_KEY_CDN_URL, '');
      const cachedS3CdnRaw: string = await PreferencesUtil.getString(PREF_KEY_S3_CDN_URL, '');
      const cachedS3BaseRaw: string = await PreferencesUtil.getString(PREF_KEY_S3_BASE_URL, '');
      const cachedEnabledReactionsRaw: string = await PreferencesUtil.getString(PREF_KEY_ENABLED_REACTIONS, '');
      if (!this.isAuthGenerationCurrent(authGeneration, 'configure_cache')) {
        return;
      }

      const cachedBase: string | null = cachedBaseRaw.length > 0 ? this.normalizePollingBaseUrl(cachedBaseRaw) : null;
      const cachedKey: string | null = cachedKeyRaw.length > 0 ? cachedKeyRaw.trim() : null;
      const cachedCdn: string | null = cachedCdnRaw.length > 0 ? cachedCdnRaw.trim() : null;
      const cachedS3Cdn: string | null = cachedS3CdnRaw.length > 0 ? cachedS3CdnRaw.trim() : null;
      const cachedS3Base: string | null = cachedS3BaseRaw.length > 0 ? cachedS3BaseRaw.trim() : null;
      const cachedEnabledReactions: string[] | null = this.parseEnabledReactions(cachedEnabledReactionsRaw);
      const effectiveCachedEnabledReactions: string[] | null = this.isLegacyEnabledReactions(cachedEnabledReactions)
        ? this.cloneEnabledReactions(DEFAULT_ENABLED_REACTIONS)
        : cachedEnabledReactions;

      if (cachedBase !== null) {
        this.longPollingBaseUrl = cachedBase;
      }
      if (cachedKey !== null && cachedKey.length > 0) {
        this.sharedSessionKey = cachedKey;
      }
      if (cachedCdn !== null && cachedCdn.length > 0) {
        this.cdnUrl = cachedCdn;
      }
      if (cachedS3Cdn !== null && cachedS3Cdn.length > 0) {
        this.s3CdnUrl = cachedS3Cdn;
      }
      if (cachedS3Base !== null && cachedS3Base.length > 0) {
        this.s3BaseUrl = cachedS3Base;
      }
      if (effectiveCachedEnabledReactions !== null && effectiveCachedEnabledReactions.length > 0) {
        this.enabledReactions = effectiveCachedEnabledReactions;
      }

      if (this.isLegacyEnabledReactions(cachedEnabledReactions)) {
        PreferencesUtil.putString(PREF_KEY_ENABLED_REACTIONS, this.joinEnabledReactions(DEFAULT_ENABLED_REACTIONS)).catch((err: Object) => {
          hilog.warn(0x0000, TAG, 'Upgrade enabledReactions cache failed: %{public}s', JSON.stringify(err));
        });
      }

      if (cachedBase !== null || (cachedKey !== null && cachedKey.length > 0)) {
        MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
        if (AppConstants.DEBUG_TRACKING) {
          hilog.info(
            0x0000,
            TAG,
            'MessageBus config loaded from cache baseUrl=%{public}s keyLen=%{public}d',
            this.longPollingBaseUrl !== null ? (this.longPollingBaseUrl as string) : '',
            this.sharedSessionKey !== null ? (this.sharedSessionKey as string).length : 0
          );
        }
      }
      if (AppConstants.DEBUG_TRACKING && (cachedCdn !== null || cachedS3Cdn !== null || cachedS3Base !== null)) {
        hilog.info(
          0x0000,
          TAG,
          'Image host config loaded from cache cdn=%{public}s s3Cdn=%{public}s s3Base=%{public}s',
          this.cdnUrl !== null ? (this.cdnUrl as string) : '',
          this.s3CdnUrl !== null ? (this.s3CdnUrl as string) : '',
          this.s3BaseUrl !== null ? (this.s3BaseUrl as string) : ''
        );
      }
    } catch (_) {
    }
  }

  private cloneEnabledReactions(source: string[] | null | undefined): string[] {
    if (source === null || source === undefined || source.length === 0) {
      return [];
    }
    const out: string[] = [];
    for (let i = 0; i < source.length; i++) {
      out.push(source[i]);
    }
    return out;
  }

  private joinEnabledReactions(source: string[] | null | undefined): string {
    if (source === null || source === undefined || source.length === 0) {
      return '';
    }
    let out: string = '';
    for (let i = 0; i < source.length; i++) {
      if (i > 0) {
        out += '|';
      }
      out += source[i];
    }
    return out;
  }

  private normalizeEnabledReactions(source: string[]): string[] {
    const out: string[] = [];
    const seen: Map<string, boolean> = new Map();
    for (let i = 0; i < source.length; i++) {
      let raw: string = source[i] !== undefined && source[i] !== null ? source[i].toString().trim().toLowerCase() : '';
      if (raw === 'thumbsup' || raw === 'thumbs_up') {
        raw = '+1';
      }
      if (raw.length === 0) {
        continue;
      }
      if (seen.has(raw)) {
        continue;
      }
      seen.set(raw, true);
      out.push(raw);
    }
    return out;
  }

  private isLegacyEnabledReactions(source: string[] | null | undefined): boolean {
    if (source === null || source === undefined) {
      return false;
    }
    const normalized: string[] = this.normalizeEnabledReactions(source);
    if (normalized.length !== LEGACY_ENABLED_REACTIONS.length) {
      return false;
    }
    for (let i = 0; i < LEGACY_ENABLED_REACTIONS.length; i++) {
      if (normalized.indexOf(LEGACY_ENABLED_REACTIONS[i]) < 0) {
        return false;
      }
    }
    return true;
  }

  private parseEnabledReactions(raw: string | null | undefined): string[] | null {
    const text: string = raw !== null && raw !== undefined ? raw.toString().trim() : '';
    if (text.length === 0) {
      return null;
    }

    let candidates: string[] = [];
    if (text.startsWith('[') && text.endsWith(']')) {
      try {
        const parsed: Object = JSON.parse(text) as Object;
        if (Array.isArray(parsed)) {
          const arr: Object[] = parsed as Object[];
          for (let i = 0; i < arr.length; i++) {
            const item: Object = arr[i];
            if (item !== null && item !== undefined) {
              candidates.push(item.toString());
            }
          }
        }
      } catch (_) {
        candidates = [];
      }
    }

    if (candidates.length === 0) {
      candidates = text.split('|');
    }

    const normalized: string[] = this.normalizeEnabledReactions(candidates);
    return normalized.length > 0 ? normalized : null;
  }

  private extractEnabledReactionsFromSiteSettings(siteSettings: Record<string, Object>): string[] | null {
    const candidates: Object[] = [];
    const snakeVal = siteSettings['discourse_reactions_enabled_reactions'];
    if (snakeVal !== undefined && snakeVal !== null) {
      candidates.push(snakeVal);
    }
    const camelVal = siteSettings['discourseReactionsEnabledReactions'];
    if (camelVal !== undefined && camelVal !== null) {
      candidates.push(camelVal);
    }

    for (let i = 0; i < candidates.length; i++) {
      const candidate: Object = candidates[i];
      if (Array.isArray(candidate)) {
        const arr: Object[] = candidate as Object[];
        const raw: string[] = [];
        for (let j = 0; j < arr.length; j++) {
          const item: Object = arr[j];
          if (item !== null && item !== undefined) {
            raw.push(item.toString());
          }
        }
        const normalized: string[] = this.normalizeEnabledReactions(raw);
        if (normalized.length > 0) {
          return normalized;
        }
        continue;
      }

      const parsed: string[] | null = this.parseEnabledReactions(candidate.toString());
      if (parsed !== null && parsed.length > 0) {
        return parsed;
      }
    }

    return null;
  }

  private persistEnabledReactionsIfChanged(prevEnabledReactions: string[] | null): void {
    const prevJoined: string = this.joinEnabledReactions(prevEnabledReactions);
    const nextJoined: string = this.joinEnabledReactions(this.enabledReactions);
    if (nextJoined.length === 0 || nextJoined === prevJoined) {
      return;
    }
    PreferencesUtil.putString(PREF_KEY_ENABLED_REACTIONS, nextJoined).catch((err: Object) => {
      hilog.warn(0x0000, TAG, 'Cache enabledReactions failed: %{public}s', JSON.stringify(err));
    });
  }

  private persistImageHostConfigIfChanged(prevCdn: string | null, prevS3Cdn: string | null, prevS3Base: string | null): void {
    if (this.cdnUrl !== null && this.cdnUrl !== prevCdn) {
      PreferencesUtil.putString(PREF_KEY_CDN_URL, this.cdnUrl as string).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache cdnUrl failed: %{public}s', JSON.stringify(err));
      });
    }
    if (this.s3CdnUrl !== null && this.s3CdnUrl !== prevS3Cdn) {
      PreferencesUtil.putString(PREF_KEY_S3_CDN_URL, this.s3CdnUrl as string).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache s3CdnUrl failed: %{public}s', JSON.stringify(err));
      });
    }
    if (this.s3BaseUrl !== null && this.s3BaseUrl !== prevS3Base) {
      PreferencesUtil.putString(PREF_KEY_S3_BASE_URL, this.s3BaseUrl as string).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache s3BaseUrl failed: %{public}s', JSON.stringify(err));
      });
    }
  }

  private decodeHtmlEntities(input: string): string {
    return input
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'");
  }

  private tryDecodeJsonEscapedString(input: string): string {
    const s: string = input;
    if (s.indexOf('\\') < 0) return s;
    try {
      // 将字符串包裹成 JSON 字符串字面量，让 JSON.parse 处理 \/、\u002F 等转义
      const safe: string = s.replaceAll('"', '\\"');
      const parsed: Object = JSON.parse(`"${safe}"`) as Object;
      return typeof parsed === 'string' ? (parsed as string) : s;
    } catch (_) {
      return s;
    }
  }

  private extractMetaContent(html: string, metaName: string): string | null {
    const reg: RegExp = new RegExp(
      `<meta[^>]+name=[\"']${metaName}[\"'][^>]+content=[\"']([^\"']+)[\"']`,
      'i'
    );
    const m: string[] | null = html.match(reg);
    if (m === null || m.length < 2) return null;
    const raw: string = m[1];
    if (raw === null || raw === undefined || raw.length === 0) return null;
    return this.decodeHtmlEntities(raw);
  }

  private extractDiscourseSetupTag(html: string): string | null {
    const reg: RegExp = new RegExp(
      `id=[\"']data-discourse-setup[\"'][^>]*>`,
      'i'
    );
    const m: string[] | null = html.match(reg);
    if (m === null || m.length < 1) return null;
    const raw: string = m[0];
    if (raw === null || raw === undefined || raw.length === 0) return null;
    return raw;
  }

  private extractDiscourseSetupAttr(tag: string, attrName: string): string | null {
    const reg: RegExp = new RegExp(
      `data-${attrName}=[\"']([^\"']+)[\"']`,
      'i'
    );
    const m: string[] | null = tag.match(reg);
    if (m === null || m.length < 2) return null;
    const raw: string = m[1];
    if (raw === null || raw === undefined || raw.length === 0) return null;

    const decoded: string = this.decodeHtmlEntities(raw).trim();
    if (decoded.length === 0) return null;
    if (decoded.endsWith('/')) {
      return decoded.substring(0, decoded.length - 1);
    }
    return decoded;
  }

  private extractCdnConfigFromHtml(html: string): void {
    const tag: string | null = this.extractDiscourseSetupTag(html);
    if (tag === null) return;

    this.cdnUrl = this.extractDiscourseSetupAttr(tag, 'cdn');
    this.s3CdnUrl = this.extractDiscourseSetupAttr(tag, 's3-cdn');
    this.s3BaseUrl = this.extractDiscourseSetupAttr(tag, 's3-base-url');

    if (this.cdnUrl !== null) {
      hilog.info(0x0000, TAG, 'cdnUrl=%{public}s', this.cdnUrl as string);
    }
    if (this.s3CdnUrl !== null || this.s3BaseUrl !== null) {
      hilog.info(
        0x0000,
        TAG,
        's3CdnUrl=%{public}s, s3BaseUrl=%{public}s',
        this.s3CdnUrl !== null ? (this.s3CdnUrl as string) : '',
        this.s3BaseUrl !== null ? (this.s3BaseUrl as string) : ''
      );
    }
  }

  private extractTurnstileSitekeyFromHtml(html: string): void {
    const match: string[] | null = html.match(/data-sitekey="([0-9a-zA-Zx_-]+)"/);
    if (match === null || match.length < 2) return;
    const sitekey: string = match[1];
    if (sitekey.length > 0) {
      CfClearanceRefreshService.getInstance().updateSitekey(sitekey);
    }
  }

  private parseMaybeJson(raw: Object): Object {
    if (raw === null || raw === undefined) return raw;
    if (typeof raw === 'string') {
      const s: string = raw as string;
      const trimmed: string = s.trim();
      if (trimmed.length === 0) return raw;
      if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return raw;
      try {
        return JSON.parse(trimmed) as Object;
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  private normalizePollingBaseUrl(url: string): string | null {
    const v: string = url.trim();
    if (v.length === 0) return null;

    // Discourse 可能返回 scheme-relative：//example.com
    let out: string = v;
    if (out.startsWith('//')) {
      let scheme: string = 'https';
      try {
        const base: string = AppConstants.BASE_URL;
        const idx: number = base.indexOf('://');
        if (idx > 0) {
          scheme = base.substring(0, idx);
        }
      } catch (_) {
      }
      out = `${scheme}:${out}`;
    } else if (out.startsWith('/') && out !== '/') {
      // 兼容相对路径（少数站点可能部署在子路径）
      const base: string = AppConstants.BASE_URL.endsWith('/')
        ? AppConstants.BASE_URL.substring(0, AppConstants.BASE_URL.length - 1)
        : AppConstants.BASE_URL;
      out = `${base}${out}`;
    } else if (out === '/') {
      // 视为“同源”，不强制写入
      return null;
    }

    if (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out.trim().length > 0 ? out : null;
  }

  private getFallbackLongPollingBaseUrl(): string | null {
    try {
      // Playwright 验证：linux.do 的 long_polling_base_url 为 https://ping.linux.do，主域 /message-bus 返回 404 属正常。
      const base: string = AppConstants.BASE_URL.trim();
      if (base.length === 0) return null;
      let scheme: string = 'https';
      let host: string = base;
      const idx: number = base.indexOf('://');
      if (idx > 0) {
        scheme = base.substring(0, idx);
        host = base.substring(idx + 3);
      }
      const slash: number = host.indexOf('/');
      if (slash >= 0) host = host.substring(0, slash);
      host = host.trim();
      if (host.toLowerCase() !== 'linux.do') return null;
      return this.normalizePollingBaseUrl(`${scheme}://ping.linux.do`);
    } catch (_) {
    }
    return null;
  }

  private async loadConfigOnly(silent: boolean): Promise<void> {
    const authGeneration: number = this.captureAuthGeneration();
    hilog.info(0x0000, TAG, 'Preload config-only %{public}s start, silent=%{public}s', PRELOAD_PATH, silent ? 'Y' : 'N');
    const httpClient: HttpClient = new HttpClient(AppConstants.BASE_URL);

    let html: string = '';
    let htmlErrText: string = '';
    try {
      html = await httpClient.getText(
        PRELOAD_PATH,
        null,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        60000,
        { silent: silent, caller: 'preloaded_latest_config' }
      );
    } catch (err) {
      try {
        htmlErrText = err !== null && err !== undefined ? err.toString() : '';
      } catch (_) {
        htmlErrText = '';
      }
      if (htmlErrText.length === 0) {
        try {
          htmlErrText = JSON.stringify(err);
        } catch (_) {
          htmlErrText = '';
        }
      }
      html = '';
      hilog.warn(0x0000, TAG, 'Preload config-only html failed: %{public}s', htmlErrText.length > 0 ? htmlErrText : 'unknown');
    }
    if (!this.isAuthGenerationCurrent(authGeneration, 'config_only_after_http')) {
      return;
    }

    if (html.length > 0) {
      const prevCdn: string | null = this.cdnUrl;
      const prevS3Cdn: string | null = this.s3CdnUrl;
      const prevS3Base: string | null = this.s3BaseUrl;
      this.extractCdnConfigFromHtml(html);
      this.persistImageHostConfigIfChanged(prevCdn, prevS3Cdn, prevS3Base);
      // Turnstile sitekey：用于 cf_clearance 自动续期（即使本次没触发 challenge，也尽量更新一次）
      this.extractTurnstileSitekeyFromHtml(html);
    }

    // shared_session_key（跨域 MessageBus）
    const nextShared: string | null = html.length > 0 ? this.extractMetaContent(html, 'shared_session_key') : null;

    // data-preloaded: 仅抽取 siteSettings.long_polling_base_url / enabled reactions（避免整串 decode + JSON.parse）
    let nextBase: string | null = null;
    let nextEnabledReactions: string[] | null = null;
    if (html.length > 0) {
      try {
        const match: string[] | null = html.match(/data-preloaded=\"([^\"]*)\"/);
        if (match !== null && match.length >= 2) {
          const encoded: string = match[1];

          // 1) 快速路径：直接从 HTML attribute（仍是 &quot; 形式，且 siteSettings 内层 JSON 会出现 \&quot;）提取
          let rawVal: string | null = null;
          let rawEnabledReactions: string | null = null;
          const baseMatch: string[] | null = encoded.match(
            /long_polling_base_url(?:\\)?&quot;\s*:\s*(?:\\)?&quot;(.+?)(?:\\)?&quot;/i
          );
          if (baseMatch !== null && baseMatch.length >= 2) {
            rawVal = this.decodeHtmlEntities(baseMatch[1]);
          }
          const enabledMatch: string[] | null = encoded.match(
            /discourse_reactions_enabled_reactions(?:\\)?&quot;\s*:\s*(?:\\)?&quot;(.+?)(?:\\)?&quot;/i
          );
          if (enabledMatch !== null && enabledMatch.length >= 2) {
            rawEnabledReactions = this.decodeHtmlEntities(enabledMatch[1]);
          }

          if (rawVal === null || rawEnabledReactions === null) {
            // 2) 兜底：仅在 fast path 缺字段时，再 decode + JSON.parse 外层并解析 siteSettings
            try {
              const decoded: string = this.decodeHtmlEntities(encoded);
              const outer: Record<string, Object> = JSON.parse(decoded) as Record<string, Object>;
              const siteSettingsRaw = outer['siteSettings'];
              const siteSettingsObj: Object | null = siteSettingsRaw !== undefined && siteSettingsRaw !== null
                ? this.parseMaybeJson(siteSettingsRaw)
                : null;
              if (siteSettingsObj !== null && siteSettingsObj !== undefined && typeof siteSettingsObj === 'object') {
                const siteSettings: Record<string, Object> = siteSettingsObj as Record<string, Object>;
                if (rawVal === null) {
                  const pollingVal = siteSettings['long_polling_base_url'];
                  if (pollingVal !== undefined && pollingVal !== null) {
                    rawVal = pollingVal.toString();
                  }
                }
                if (rawEnabledReactions === null) {
                  nextEnabledReactions = this.extractEnabledReactionsFromSiteSettings(siteSettings);
                }
              }
            } catch (_) {
              if (rawVal === null) {
                rawVal = null;
              }
            }
          }

          if (rawVal !== null && rawVal.length > 0) {
            const unescaped: string = this.tryDecodeJsonEscapedString(rawVal);
            nextBase = this.normalizePollingBaseUrl(unescaped);
          }
          if (rawEnabledReactions !== null && rawEnabledReactions.length > 0) {
            nextEnabledReactions = this.parseEnabledReactions(rawEnabledReactions);
          }
        }
      } catch (_) {
        nextBase = null;
      }
    }
    if (!this.isAuthGenerationCurrent(authGeneration, 'config_only_before_apply')) {
      return;
    }

    // 兜底：在 CF challenge（silent）导致 HTML 取不到时，给 linux.do 一个可靠的默认 long_polling_base_url
    if (nextBase === null) {
      nextBase = this.getFallbackLongPollingBaseUrl();
    }

    const prevBase: string | null = this.longPollingBaseUrl;
    const prevKey: string | null = this.sharedSessionKey;
    const prevEnabledReactions: string[] | null = this.enabledReactions;

    if (nextBase !== null) {
      this.longPollingBaseUrl = nextBase;
    }
    if (nextShared !== null && nextShared.length > 0) {
      this.sharedSessionKey = nextShared;
    }
    if (nextEnabledReactions !== null && nextEnabledReactions.length > 0) {
      this.enabledReactions = nextEnabledReactions;
    }

    // configure()：即使只拿到其中一个字段，也可提高成功率（另一项可由缓存/后续刷新补齐）
    try {
      MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
    } catch (_) {
    }

    // 写入缓存：只在拿到非空值时更新，避免覆盖已有可用缓存
    if (nextBase !== null && nextBase !== prevBase) {
      PreferencesUtil.putString(PREF_KEY_LONG_POLLING_BASE_URL, nextBase).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache longPollingBaseUrl failed: %{public}s', JSON.stringify(err));
      });
    }
    if (nextShared !== null && nextShared.length > 0 && nextShared !== prevKey) {
      PreferencesUtil.putString(PREF_KEY_SHARED_SESSION_KEY, nextShared).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache sharedSessionKey failed: %{public}s', JSON.stringify(err));
      });
    }
    this.persistEnabledReactionsIfChanged(prevEnabledReactions);

    if (AppConstants.DEBUG_TRACKING) {
      const baseChanged: boolean = nextBase !== null && nextBase !== prevBase;
      const keyChanged: boolean = nextShared !== null && nextShared.length > 0 && nextShared !== prevKey;
      if (baseChanged || keyChanged || htmlErrText.length > 0) {
        hilog.info(
          0x0000,
          TAG,
          'Config-only updated baseChanged=%{public}s keyChanged=%{public}s baseUrl=%{public}s keyLen=%{public}d htmlErr=%{public}s',
          baseChanged ? 'Y' : 'N',
          keyChanged ? 'Y' : 'N',
          this.longPollingBaseUrl !== null ? (this.longPollingBaseUrl as string) : '',
          this.sharedSessionKey !== null ? (this.sharedSessionKey as string).length : 0,
          htmlErrText.length > 0 ? htmlErrText : '-'
        );
      }
    }

    this.configLoaded = true;
  }

  private async load(silent: boolean): Promise<void> {
    const authGeneration: number = this.captureAuthGeneration();
    hilog.info(0x0000, TAG, 'Preload %{public}s start, silent=%{public}s', PRELOAD_PATH, silent ? 'Y' : 'N');
    const httpClient: HttpClient = new HttpClient(AppConstants.BASE_URL);
    const html: string = await httpClient.getText(
      PRELOAD_PATH,
      null,
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      60000,
      { silent: silent, caller: 'preloaded_latest' }
    );
    if (!this.isAuthGenerationCurrent(authGeneration, 'full_after_http')) {
      return;
    }

    // data-discourse-setup（CDN / S3 CDN）
    const prevCdn: string | null = this.cdnUrl;
    const prevS3Cdn: string | null = this.s3CdnUrl;
    const prevS3Base: string | null = this.s3BaseUrl;
    this.extractCdnConfigFromHtml(html);
    this.persistImageHostConfigIfChanged(prevCdn, prevS3Cdn, prevS3Base);
    this.extractTurnstileSitekeyFromHtml(html);

    // shared_session_key（跨域 MessageBus）
    this.sharedSessionKey = this.extractMetaContent(html, 'shared_session_key');

    // data-preloaded
    const match: string[] | null = html.match(/data-preloaded="([^"]*)"/);
    if (match === null || match.length < 2) {
      hilog.error(0x0000, TAG, 'No data-preloaded found');
      this.loaded = true;
      return;
    }

    const encoded: string = match[1];
    const decoded: string = this.decodeHtmlEntities(encoded);

    let outer: Record<string, Object> | null = null;
    try {
      outer = JSON.parse(decoded) as Record<string, Object>;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Parse data-preloaded failed: %{public}s', JSON.stringify(err));
      this.loaded = true;
      return;
    }

    const prevEnabledReactions: string[] | null = this.enabledReactions;

    // siteSettings.long_polling_base_url / discourse_reactions_enabled_reactions
    const siteSettingsRaw = outer['siteSettings'];
    const siteSettingsObj: Object | null = siteSettingsRaw !== undefined && siteSettingsRaw !== null
      ? this.parseMaybeJson(siteSettingsRaw)
      : null;
    if (siteSettingsObj !== null && siteSettingsObj !== undefined && typeof siteSettingsObj === 'object') {
      const siteSettings: Record<string, Object> = siteSettingsObj as Record<string, Object>;
      const pollingVal = siteSettings['long_polling_base_url'];
      if (pollingVal !== undefined && pollingVal !== null) {
        const normalized: string | null = this.normalizePollingBaseUrl(pollingVal.toString());
        if (normalized !== null) {
          this.longPollingBaseUrl = normalized;
          hilog.info(0x0000, TAG, 'longPollingBaseUrl=%{public}s', normalized);
        }
      }
      const nextEnabledReactions: string[] | null = this.extractEnabledReactionsFromSiteSettings(siteSettings);
      if (nextEnabledReactions !== null && nextEnabledReactions.length > 0) {
        this.enabledReactions = nextEnabledReactions;
      }
    }

    // topicTrackingStateMeta（频道初始 message_id）
    const metaRaw = outer['topicTrackingStateMeta'];
    const metaObj: Object | null = metaRaw !== undefined && metaRaw !== null ? this.parseMaybeJson(metaRaw) : null;
    if (metaObj !== null && metaObj !== undefined && typeof metaObj === 'object') {
      const metaJson: Record<string, Object> = metaObj as Record<string, Object>;
      const keys: string[] = Object.keys(metaJson);
      const map: Map<string, number> = new Map();
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        const v: Object = metaJson[k];
        if (v === undefined || v === null) continue;
        const num: number = Number(v.toString());
        if (!isNaN(num)) {
          map.set(k, num);
        }
      }
      if (map.size > 0) {
        this.topicTrackingStateMeta = map;
        hilog.info(0x0000, TAG, 'topicTrackingStateMeta size=%{public}d', map.size);
      }
    }

    // topicTrackingStates（追踪状态数组）
    const statesRaw = outer['topicTrackingStates'];
    const statesObj: Object | null = statesRaw !== undefined && statesRaw !== null ? this.parseMaybeJson(statesRaw) : null;
    if (statesObj !== null && statesObj !== undefined && Array.isArray(statesObj)) {
      const arr: Object[] = statesObj as Object[];
      const list: Record<string, Object>[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item !== null && item !== undefined && typeof item === 'object') {
          list.push(item as Record<string, Object>);
        }
      }
      this.topicTrackingStates = list;
      hilog.info(0x0000, TAG, 'topicTrackingStates size=%{public}d', list.length);
    }
    if (!this.isAuthGenerationCurrent(authGeneration, 'full_before_apply')) {
      return;
    }

    this.loaded = true;
    this.configLoaded = true;
    try {
      MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
    } catch (_) {
    }
    if (this.longPollingBaseUrl !== null) {
      PreferencesUtil.putString(PREF_KEY_LONG_POLLING_BASE_URL, this.longPollingBaseUrl as string).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache longPollingBaseUrl failed: %{public}s', JSON.stringify(err));
      });
    }
    if (this.sharedSessionKey !== null && (this.sharedSessionKey as string).length > 0) {
      PreferencesUtil.putString(PREF_KEY_SHARED_SESSION_KEY, this.sharedSessionKey as string).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache sharedSessionKey failed: %{public}s', JSON.stringify(err));
      });
    }
    this.persistEnabledReactionsIfChanged(prevEnabledReactions);
    CfClearanceRefreshService.getInstance().startIfPossible();
  }
}
