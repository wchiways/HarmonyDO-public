import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from './PreferencesUtil';

const TAG: string = 'ComposerEmojiPreferences';

export class ComposerEmojiPreferences {
  private static readonly KEY_RECENT_EMOJI_NAMES: string = 'composer_recent_emoji_names';
  private static readonly MAX_RECENT_COUNT: number = 30;

  private static normalizeNames(names: string[]): string[] {
    const out: string[] = [];
    const seen: Map<string, boolean> = new Map();
    for (let i = 0; i < names.length; i++) {
      const raw: string = names[i] !== undefined && names[i] !== null ? names[i].toString() : '';
      const trimmed: string = raw.trim();
      if (trimmed.length === 0 || seen.has(trimmed)) {
        continue;
      }
      seen.set(trimmed, true);
      out.push(trimmed);
      if (out.length >= ComposerEmojiPreferences.MAX_RECENT_COUNT) {
        break;
      }
    }
    return out;
  }

  static async loadRecentNames(): Promise<string[]> {
    await PreferencesUtil.ensureInit();
    const raw: string = await PreferencesUtil.getString(ComposerEmojiPreferences.KEY_RECENT_EMOJI_NAMES, '[]');
    const trimmed: string = raw.trim();
    if (trimmed.length === 0) {
      return [];
    }

    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const list: string[] = [];
      const arr: Object[] = parsed as Object[];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined) {
          continue;
        }
        list.push(item.toString());
      }
      return ComposerEmojiPreferences.normalizeNames(list);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load recent emojis failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  static async saveRecentName(name: string): Promise<void> {
    const trimmed: string = name !== undefined && name !== null ? name.trim() : '';
    if (trimmed.length === 0) {
      return;
    }
    const next: string[] = [trimmed];
    const current: string[] = await ComposerEmojiPreferences.loadRecentNames();
    for (let i = 0; i < current.length; i++) {
      if (current[i] !== trimmed) {
        next.push(current[i]);
      }
    }
    const normalized: string[] = ComposerEmojiPreferences.normalizeNames(next);
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(
      ComposerEmojiPreferences.KEY_RECENT_EMOJI_NAMES,
      JSON.stringify(normalized)
    );
  }
}
