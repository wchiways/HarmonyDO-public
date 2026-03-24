function readString(json: Record<string, Object>, key: string): string {
  const value = json[key];
  return value !== undefined && value !== null ? value.toString() : '';
}

function readNumber(json: Record<string, Object>, key: string): number {
  const value = json[key];
  if (value === undefined || value === null) {
    return 0;
  }
  const num: number = Number(value.toString());
  return isNaN(num) ? 0 : Math.floor(num);
}

function readBoolean(json: Record<string, Object>, key: string): boolean {
  const value = json[key];
  if (value === undefined || value === null) {
    return false;
  }
  if (typeof value === 'boolean') {
    return value as boolean;
  }
  const normalized: string = value.toString().trim().toLowerCase();
  return normalized === 'true' || normalized === '1';
}

function escapeMarkdownAlt(text: string): string {
  const raw: string = text !== undefined && text !== null ? text : '';
  return raw.replace(/\]/g, '\\]');
}

export class StickerMarketIndex {
  totalPages: number = 0;
  pageSize: number = 0;
  totalGroups: number = 0;

  static fromJson(json: Record<string, Object>): StickerMarketIndex {
    const index: StickerMarketIndex = new StickerMarketIndex();
    index.totalPages = readNumber(json, 'totalPages');
    index.pageSize = readNumber(json, 'pageSize');
    index.totalGroups = readNumber(json, 'totalGroups');
    return index;
  }
}

export class StickerGroup {
  id: string = '';
  name: string = '';
  icon: string = '';
  order: number = 0;
  emojiCount: number = 0;
  isArchived: boolean = false;

  static fromJson(json: Record<string, Object>): StickerGroup {
    const group: StickerGroup = new StickerGroup();
    group.id = readString(json, 'id');
    group.name = readString(json, 'name');
    group.icon = readString(json, 'icon');
    group.order = readNumber(json, 'order');
    group.emojiCount = readNumber(json, 'emojiCount');
    group.isArchived = readBoolean(json, 'isArchived');
    return group;
  }
}

export class StickerItem {
  id: string = '';
  name: string = '';
  url: string = '';
  width: number = 0;
  height: number = 0;
  groupId: string = '';

  static fromJson(json: Record<string, Object>): StickerItem {
    const item: StickerItem = new StickerItem();
    item.id = readString(json, 'id');
    item.name = readString(json, 'name');
    item.url = readString(json, 'url');
    item.width = readNumber(json, 'width');
    item.height = readNumber(json, 'height');
    item.groupId = readString(json, 'groupId');
    return item;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['id'] = this.id;
    json['name'] = this.name;
    json['url'] = this.url;
    json['width'] = this.width;
    json['height'] = this.height;
    json['groupId'] = this.groupId;
    return json;
  }

  toMarkdown(): string {
    const safeName: string = escapeMarkdownAlt(this.name.trim().length > 0 ? this.name : 'sticker');
    const safeUrl: string = this.url.trim();
    if (safeUrl.length === 0) {
      return '';
    }
    if (this.width > 0 && this.height > 0) {
      return `![${safeName}|${this.width}x${this.height},30%](${safeUrl})`;
    }
    return `![${safeName}](${safeUrl})`;
  }
}

export class StickerGroupDetail {
  id: string = '';
  name: string = '';
  icon: string = '';
  emojis: StickerItem[] = [];

  static fromJson(json: Record<string, Object>): StickerGroupDetail {
    const detail: StickerGroupDetail = new StickerGroupDetail();
    detail.id = readString(json, 'id');
    detail.name = readString(json, 'name');
    detail.icon = readString(json, 'icon');

    const emojisVal = json['emojis'];
    if (emojisVal !== undefined && emojisVal !== null && Array.isArray(emojisVal)) {
      const arr: Object[] = emojisVal as Object[];
      const list: StickerItem[] = [];
      for (let i = 0; i < arr.length; i++) {
        const row: Object = arr[i];
        if (row === undefined || row === null || typeof row !== 'object') {
          continue;
        }
        list.push(StickerItem.fromJson(row as Record<string, Object>));
      }
      detail.emojis = list;
    }
    return detail;
  }
}
