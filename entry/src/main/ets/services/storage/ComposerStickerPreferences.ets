import { hilog } from '@kit.PerformanceAnalysisKit';
import { StickerItem } from '../../models/Sticker';
import { PreferencesUtil } from './PreferencesUtil';

const TAG: string = 'ComposerStickerPreferences';

export class ComposerStickerPreferences {
  private static readonly KEY_SUBSCRIBED_GROUP_IDS: string = 'composer_sticker_subscribed_group_ids';
  private static readonly KEY_RECENT_STICKERS: string = 'composer_recent_stickers';
  private static readonly MAX_RECENT_COUNT: number = 30;

  private static normalizeGroupIds(groupIds: string[]): string[] {
    const out: string[] = [];
    const seen: Map<string, boolean> = new Map();
    for (let i = 0; i < groupIds.length; i++) {
      const raw: string = groupIds[i] !== undefined && groupIds[i] !== null ? groupIds[i].toString() : '';
      const trimmed: string = raw.trim();
      if (trimmed.length === 0 || seen.has(trimmed)) {
        continue;
      }
      seen.set(trimmed, true);
      out.push(trimmed);
    }
    return out;
  }

  private static normalizeRecentStickers(stickers: StickerItem[]): StickerItem[] {
    const out: StickerItem[] = [];
    const seen: Map<string, boolean> = new Map();
    for (let i = 0; i < stickers.length; i++) {
      const item: StickerItem = stickers[i];
      const dedupeKey: string = item.id.trim().length > 0 ? item.id.trim() : item.url.trim();
      if (dedupeKey.length === 0 || seen.has(dedupeKey)) {
        continue;
      }
      seen.set(dedupeKey, true);
      out.push(item);
      if (out.length >= ComposerStickerPreferences.MAX_RECENT_COUNT) {
        break;
      }
    }
    return out;
  }

  static async loadSubscribedGroupIds(): Promise<string[]> {
    await PreferencesUtil.ensureInit();
    const raw: string = await PreferencesUtil.getString(ComposerStickerPreferences.KEY_SUBSCRIBED_GROUP_IDS, '[]');
    const trimmed: string = raw.trim();
    if (trimmed.length === 0) {
      return [];
    }

    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const arr: Object[] = parsed as Object[];
      const list: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === undefined || item === null) {
          continue;
        }
        list.push(item.toString());
      }
      return ComposerStickerPreferences.normalizeGroupIds(list);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load subscribed sticker groups failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  static async saveSubscribedGroupIds(groupIds: string[]): Promise<void> {
    const normalized: string[] = ComposerStickerPreferences.normalizeGroupIds(groupIds);
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(
      ComposerStickerPreferences.KEY_SUBSCRIBED_GROUP_IDS,
      JSON.stringify(normalized)
    );
  }

  static async subscribeGroup(groupId: string): Promise<string[]> {
    const trimmed: string = groupId !== undefined && groupId !== null ? groupId.trim() : '';
    if (trimmed.length === 0) {
      return await ComposerStickerPreferences.loadSubscribedGroupIds();
    }
    const current: string[] = await ComposerStickerPreferences.loadSubscribedGroupIds();
    if (current.indexOf(trimmed) >= 0) {
      return current;
    }
    const next: string[] = [...current, trimmed];
    await ComposerStickerPreferences.saveSubscribedGroupIds(next);
    return await ComposerStickerPreferences.loadSubscribedGroupIds();
  }

  static async unsubscribeGroup(groupId: string): Promise<string[]> {
    const trimmed: string = groupId !== undefined && groupId !== null ? groupId.trim() : '';
    if (trimmed.length === 0) {
      return await ComposerStickerPreferences.loadSubscribedGroupIds();
    }
    const current: string[] = await ComposerStickerPreferences.loadSubscribedGroupIds();
    const next: string[] = [];
    for (let i = 0; i < current.length; i++) {
      if (current[i] !== trimmed) {
        next.push(current[i]);
      }
    }
    await ComposerStickerPreferences.saveSubscribedGroupIds(next);
    return await ComposerStickerPreferences.loadSubscribedGroupIds();
  }

  static async loadRecentStickers(): Promise<StickerItem[]> {
    await PreferencesUtil.ensureInit();
    const raw: string = await PreferencesUtil.getString(ComposerStickerPreferences.KEY_RECENT_STICKERS, '[]');
    const trimmed: string = raw.trim();
    if (trimmed.length === 0) {
      return [];
    }

    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const arr: Object[] = parsed as Object[];
      const list: StickerItem[] = [];
      for (let i = 0; i < arr.length; i++) {
        const row: Object = arr[i];
        if (row === undefined || row === null || typeof row !== 'object') {
          continue;
        }
        list.push(StickerItem.fromJson(row as Record<string, Object>));
      }
      return ComposerStickerPreferences.normalizeRecentStickers(list);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load recent stickers failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  static async saveRecentSticker(sticker: StickerItem): Promise<void> {
    const markdown: string = sticker.toMarkdown();
    if (markdown.length === 0) {
      return;
    }

    const next: StickerItem[] = [];
    next.push(sticker);
    const current: StickerItem[] = await ComposerStickerPreferences.loadRecentStickers();
    for (let i = 0; i < current.length; i++) {
      if (current[i].id !== sticker.id && current[i].url !== sticker.url) {
        next.push(current[i]);
      }
    }
    const normalized: StickerItem[] = ComposerStickerPreferences.normalizeRecentStickers(next);
    const jsonList: Record<string, Object>[] = [];
    for (let i = 0; i < normalized.length; i++) {
      jsonList.push(normalized[i].toJson());
    }
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(
      ComposerStickerPreferences.KEY_RECENT_STICKERS,
      JSON.stringify(jsonList)
    );
  }
}
