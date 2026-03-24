import { ComposerImageService } from './ComposerImageService';
import { ApiClient } from '../../services/network/ApiClient';

export class ComposerImageUploadService {
  static async pickAndUploadMarkdowns(
    maxSelectNumber: number = 9,
    onProgress: ((current: number, total: number) => void) | null = null
  ): Promise<string[]> {
    const selected = await ComposerImageService.pickImages(maxSelectNumber);
    if (selected.length === 0) {
      return [];
    }

    const markdowns: string[] = [];
    for (let i = 0; i < selected.length; i++) {
      const current: number = i + 1;
      if (onProgress !== null) {
        onProgress(current, selected.length);
      }

      const asset = await ComposerImageService.readImageAsset(selected[i].uri, selected[i].displayName);
      const uploaded = await ApiClient.getInstance().uploadComposerImage(
        asset.bytes,
        asset.displayName,
        asset.mimeType,
        asset.width,
        asset.height
      );
      const markdown: string = uploaded.toMarkdown(asset.displayName);
      if (markdown.length > 0) {
        markdowns.push(markdown);
      }
    }
    return markdowns;
  }
}
