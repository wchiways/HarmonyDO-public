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
  if (isNaN(num) || num <= 0) {
    return 0;
  }
  return Math.floor(num);
}

function escapeMarkdownAlt(text: string): string {
  const raw: string = text !== undefined && text !== null ? text : '';
  return raw
    .replace(/\[/g, '\\[')
    .replace(/\]/g, '\\]');
}

export class UploadedImage {
  shortUrl: string = '';
  url: string = '';
  originalFilename: string = '';
  width: number = 0;
  height: number = 0;
  thumbnailWidth: number = 0;
  thumbnailHeight: number = 0;

  static fromJson(
    json: Record<string, Object>,
    fallbackFileName: string = '',
    fallbackWidth: number = 0,
    fallbackHeight: number = 0
  ): UploadedImage {
    const result: UploadedImage = new UploadedImage();
    result.shortUrl = readString(json, 'short_url');
    result.url = readString(json, 'url');
    result.originalFilename = readString(json, 'original_filename');
    if (result.originalFilename.length === 0) {
      result.originalFilename = fallbackFileName;
    }
    result.width = readNumber(json, 'width');
    result.height = readNumber(json, 'height');
    result.thumbnailWidth = readNumber(json, 'thumbnail_width');
    result.thumbnailHeight = readNumber(json, 'thumbnail_height');
    if (result.width <= 0) {
      result.width = fallbackWidth;
    }
    if (result.height <= 0) {
      result.height = fallbackHeight;
    }
    return result;
  }

  hasUsableUrl(): boolean {
    return this.shortUrl.trim().length > 0 || this.url.trim().length > 0;
  }

  getMarkdownUrl(): string {
    const shortUrl: string = this.shortUrl.trim();
    if (shortUrl.length > 0) {
      return shortUrl;
    }
    return this.url.trim();
  }

  toMarkdown(altText: string = ''): string {
    const markdownUrl: string = this.getMarkdownUrl();
    if (markdownUrl.length === 0) {
      return '';
    }

    const displayAlt: string = altText.trim().length > 0
      ? altText.trim()
      : (this.originalFilename.trim().length > 0 ? this.originalFilename.trim() : 'image');
    const safeAlt: string = escapeMarkdownAlt(displayAlt);
    const width: number = this.thumbnailWidth > 0 ? this.thumbnailWidth : this.width;
    const height: number = this.thumbnailHeight > 0 ? this.thumbnailHeight : this.height;
    if (width > 0 && height > 0) {
      return `![${safeAlt}|${width}x${height}](${markdownUrl})`;
    }
    return `![${safeAlt}](${markdownUrl})`;
  }
}
