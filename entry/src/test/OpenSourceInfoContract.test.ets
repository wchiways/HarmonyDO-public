import { describe, it, expect } from '@ohos/hypium';
import {
  buildOpenSourceSections,
  OpenSourceItemActionType
} from '../main/ets/common/utils/OpenSourceInfoContract';

export default function openSourceInfoContractTest() {
  describe('openSourceInfoContractTest', () => {
    it('builds open source sections without participation group', 0, () => {
      const sections = buildOpenSourceSections();

      expect(sections.length).assertEqual(2);
      expect(sections[0].title).assertEqual('项目说明');
      expect(sections[1].title).assertEqual('开源合规');
    });

    it('keeps all info items non-clickable in remaining sections', 0, () => {
      const sections = buildOpenSourceSections();

      for (let i = 0; i < sections.length; i++) {
        const section = sections[i];
        for (let j = 0; j < section.items.length; j++) {
          const item = section.items[j];
          expect(item.actionType).assertEqual(OpenSourceItemActionType.None);
          expect(item.url).assertEqual('');
        }
      }
    });

    it('keeps disclaimer as non-clickable info item', 0, () => {
      const sections = buildOpenSourceSections();
      const compliance = sections[1];
      const disclaimer = compliance.items[1];

      expect(disclaimer.title).assertEqual('免责声明');
      expect(disclaimer.actionType).assertEqual(OpenSourceItemActionType.None);
      expect(disclaimer.url).assertEqual('');
    });
  });
}
