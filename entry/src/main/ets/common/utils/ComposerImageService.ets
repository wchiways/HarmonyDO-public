import fileIo from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'ComposerImageService';
const DEFAULT_MAX_SELECT_NUMBER: number = 9;

function clampSelectNumber(value: number): number {
  if (isNaN(value) || value <= 0) {
    return 1;
  }
  if (value > 20) {
    return 20;
  }
  return Math.floor(value);
}

function trimFileScheme(uriOrPath: string): string {
  const raw: string = uriOrPath !== undefined && uriOrPath !== null ? uriOrPath.trim() : '';
  if (raw.startsWith('file://')) {
    return raw.substring('file://'.length);
  }
  return raw;
}

function decodeUriName(input: string): string {
  const raw: string = input !== undefined && input !== null ? input.trim() : '';
  if (raw.length === 0) {
    return '';
  }
  try {
    return decodeURIComponent(raw);
  } catch (_) {
    return raw;
  }
}

function buildFallbackFileName(uri: string): string {
  const raw: string = trimFileScheme(uri);
  if (raw.length === 0) {
    return `image_${Date.now()}.jpg`;
  }
  const queryIndex: number = raw.indexOf('?');
  const safeRaw: string = queryIndex >= 0 ? raw.substring(0, queryIndex) : raw;
  const slashIndex: number = Math.max(safeRaw.lastIndexOf('/'), safeRaw.lastIndexOf('\\'));
  const name: string = slashIndex >= 0 ? safeRaw.substring(slashIndex + 1) : safeRaw;
  const decoded: string = decodeUriName(name);
  return decoded.trim().length > 0 ? decoded : `image_${Date.now()}.jpg`;
}

function guessMimeType(fileName: string): string {
  const lower: string = fileName !== undefined && fileName !== null ? fileName.trim().toLowerCase() : '';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  if (lower.endsWith('.jpeg') || lower.endsWith('.jpg')) return 'image/jpeg';
  return 'image/jpeg';
}

function sliceArrayBuffer(buffer: ArrayBuffer, length: number): ArrayBuffer {
  if (length >= buffer.byteLength) {
    return buffer;
  }
  return buffer.slice(0, length);
}

export class ComposerSelectedImage {
  uri: string = '';
  displayName: string = '';
}

export class ComposerImageAsset {
  uri: string = '';
  displayName: string = '';
  mimeType: string = 'image/jpeg';
  bytes: ArrayBuffer = new ArrayBuffer(0);
  width: number = 0;
  height: number = 0;
}

export class ComposerImageService {
  static async pickImages(maxSelectNumber: number = DEFAULT_MAX_SELECT_NUMBER): Promise<ComposerSelectedImage[]> {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = clampSelectNumber(maxSelectNumber);
    options.isSearchSupported = true;
    options.isPhotoTakingSupported = true;
    options.isPreviewForSingleSelectionSupported = true;

    const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    const uris: string[] = result.photoUris;
    const selected: ComposerSelectedImage[] = [];
    for (let i = 0; i < uris.length; i++) {
      const uri: string = uris[i] !== undefined && uris[i] !== null ? uris[i].trim() : '';
      if (uri.length === 0) {
        continue;
      }
      const item: ComposerSelectedImage = new ComposerSelectedImage();
      item.uri = uri;
      item.displayName = ComposerImageService.resolveDisplayName(uri);
      selected.push(item);
    }
    return selected;
  }

  static async readImageAsset(uri: string, displayName: string = ''): Promise<ComposerImageAsset> {
    const safeUri: string = uri !== undefined && uri !== null ? uri.trim() : '';
    if (safeUri.length === 0) {
      throw new Error('图片 URI 不可用');
    }

    const file = fileIo.openSync(safeUri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      const size: number = stat.size;
      if (size <= 0) {
        throw new Error('图片文件为空');
      }

      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const bytesRead: number = fileIo.readSync(file.fd, buffer);
      if (bytesRead <= 0) {
        throw new Error('读取图片失败');
      }
      const bytes: ArrayBuffer = sliceArrayBuffer(buffer, bytesRead);

      let width: number = 0;
      let height: number = 0;
      try {
        const source: image.ImageSource = image.createImageSource(bytes);
        const info: image.ImageInfo = await source.getImageInfo();
        width = info.size.width;
        height = info.size.height;
      } catch (err) {
        hilog.warn(0x0000, TAG, 'getImageInfo failed: %{public}s', JSON.stringify(err));
      }

      const resolvedName: string = displayName.trim().length > 0
        ? displayName.trim()
        : (file.name.trim().length > 0 ? file.name.trim() : buildFallbackFileName(safeUri));

      const asset: ComposerImageAsset = new ComposerImageAsset();
      asset.uri = safeUri;
      asset.displayName = resolvedName;
      asset.mimeType = guessMimeType(resolvedName);
      asset.bytes = bytes;
      asset.width = width;
      asset.height = height;
      return asset;
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (_) {
      }
    }
  }

  private static resolveDisplayName(uri: string): string {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const name: string = file.name;
        if (name.trim().length > 0) {
          return name.trim();
        }
      } finally {
        try {
          fileIo.closeSync(file);
        } catch (_) {
        }
      }
    } catch (_) {
    }
    return buildFallbackFileName(uri);
  }
}
