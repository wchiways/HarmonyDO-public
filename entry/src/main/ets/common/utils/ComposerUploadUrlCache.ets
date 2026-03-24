export class ComposerUploadUrlCache {
  private static readonly shortUrlMap: Map<string, string> = new Map();

  static register(shortUrl: string, resolvedUrl: string): void {
    const shortKey: string = shortUrl !== undefined && shortUrl !== null ? shortUrl.trim() : '';
    const targetUrl: string = resolvedUrl !== undefined && resolvedUrl !== null ? resolvedUrl.trim() : '';
    if (shortKey.length === 0 || targetUrl.length === 0) {
      return;
    }
    ComposerUploadUrlCache.shortUrlMap.set(shortKey, targetUrl);
  }

  static resolve(url: string): string {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) {
      return '';
    }
    if (ComposerUploadUrlCache.shortUrlMap.has(raw)) {
      return ComposerUploadUrlCache.shortUrlMap.get(raw) as string;
    }
    return raw;
  }
}
