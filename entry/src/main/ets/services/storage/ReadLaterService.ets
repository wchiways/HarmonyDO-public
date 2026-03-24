import { hilog } from '@kit.PerformanceAnalysisKit';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { PreferencesUtil } from './PreferencesUtil';

const TAG: string = 'ReadLaterService';
const KEY_READ_LATER_ITEMS: string = 'read_later_items_v1';

export const MAX_READ_LATER_ITEMS: number = 10;

export class ReadLaterItem {
  topicId: number = 0;
  title: string = '';
  postNumber: number = 0;
  addedAt: Date = new Date();

  constructor() {
  }

  static fromJson(json: Record<string, Object>): ReadLaterItem {
    const item: ReadLaterItem = new ReadLaterItem();
    item.topicId = json['topic_id'] !== undefined && json['topic_id'] !== null
      ? Number(json['topic_id'].toString())
      : 0;
    item.title = json['title'] !== undefined && json['title'] !== null
      ? json['title'].toString()
      : '';
    item.postNumber = json['post_number'] !== undefined && json['post_number'] !== null
      ? Number(json['post_number'].toString())
      : 0;
    item.addedAt = TimeUtils.parseUtcTime(
      json['added_at'] !== undefined && json['added_at'] !== null ? json['added_at'].toString() : ''
    ) ?? new Date();
    return item;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['topic_id'] = this.topicId;
    json['title'] = this.title;
    json['post_number'] = this.postNumber;
    json['added_at'] = this.addedAt.toISOString();
    return json;
  }

  clone(): ReadLaterItem {
    const copy: ReadLaterItem = new ReadLaterItem();
    copy.topicId = this.topicId;
    copy.title = this.title;
    copy.postNumber = this.postNumber;
    copy.addedAt = new Date(this.addedAt.getTime());
    return copy;
  }
}

export class ReadLaterService {
  private static instance: ReadLaterService | null = null;

  private initialized: boolean = false;
  private items: ReadLaterItem[] = [];
  private listeners: (() => void)[] = [];
  private notifyScheduled: boolean = false;

  private constructor() {
  }

  static getInstance(): ReadLaterService {
    if (ReadLaterService.instance === null) {
      ReadLaterService.instance = new ReadLaterService();
    }
    return ReadLaterService.instance;
  }

  private notifyListeners(): void {
    if (this.notifyScheduled) {
      return;
    }
    this.notifyScheduled = true;
    setTimeout(() => {
      this.notifyScheduled = false;
      for (let i = 0; i < this.listeners.length; i++) {
        try {
          this.listeners[i]();
        } catch (_) {
        }
      }
    }, 0);
  }

  addListener(listener: () => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] === listener) {
        return;
      }
    }
    this.listeners.push(listener);
  }

  removeListener(listener: () => void): void {
    const next: (() => void)[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  async ensureLoaded(): Promise<void> {
    if (this.initialized) {
      return;
    }
    await PreferencesUtil.ensureInit();
    const raw: string = await PreferencesUtil.getString(KEY_READ_LATER_ITEMS, '');
    this.items = this.parseItems(raw);
    this.initialized = true;
  }

  private parseItems(raw: string): ReadLaterItem[] {
    if (raw.trim().length === 0) {
      return [];
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const next: ReadLaterItem[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const itemVal: Object = parsed[i];
        if (itemVal === null || itemVal === undefined || typeof itemVal !== 'object') {
          continue;
        }
        const item: ReadLaterItem = ReadLaterItem.fromJson(itemVal as Record<string, Object>);
        if (item.topicId > 0) {
          next.push(item);
        }
      }
      return next;
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Parse read later items failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  private async persist(): Promise<void> {
    const list: Object[] = [];
    for (let i = 0; i < this.items.length; i++) {
      list.push(this.items[i].toJson() as Object);
    }
    await PreferencesUtil.putString(KEY_READ_LATER_ITEMS, JSON.stringify(list));
  }

  getItemsSync(): ReadLaterItem[] {
    const next: ReadLaterItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      next.push(this.items[i].clone());
    }
    return next;
  }

  async getItems(): Promise<ReadLaterItem[]> {
    await this.ensureLoaded();
    return this.getItemsSync();
  }

  hasTopicSync(topicId: number): boolean {
    if (topicId <= 0) {
      return false;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].topicId === topicId) {
        return true;
      }
    }
    return false;
  }

  async hasTopic(topicId: number): Promise<boolean> {
    await this.ensureLoaded();
    return this.hasTopicSync(topicId);
  }

  async addOrUpdate(topicId: number, title: string, postNumber: number = 0): Promise<boolean> {
    await this.ensureLoaded();
    if (topicId <= 0) {
      return false;
    }

    const normalizedTitle: string = title.trim().length > 0 ? title.trim() : `话题 #${topicId}`;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].topicId === topicId) {
        this.items[i].title = normalizedTitle;
        this.items[i].postNumber = Math.max(0, postNumber);
        this.items[i].addedAt = new Date();
        await this.persist();
        this.notifyListeners();
        return true;
      }
    }

    if (this.items.length >= MAX_READ_LATER_ITEMS) {
      return false;
    }

    const item: ReadLaterItem = new ReadLaterItem();
    item.topicId = topicId;
    item.title = normalizedTitle;
    item.postNumber = Math.max(0, postNumber);
    item.addedAt = new Date();
    this.items = [item, ...this.items];
    await this.persist();
    this.notifyListeners();
    return true;
  }

  async remove(topicId: number): Promise<void> {
    await this.ensureLoaded();
    if (topicId <= 0) {
      return;
    }
    const next: ReadLaterItem[] = [];
    let changed: boolean = false;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].topicId === topicId) {
        changed = true;
        continue;
      }
      next.push(this.items[i]);
    }
    if (!changed) {
      return;
    }
    this.items = next;
    await this.persist();
    this.notifyListeners();
  }
}
