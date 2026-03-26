import { describe, it, expect } from '@ohos/hypium';
import { parseMessageBusError } from '../main/ets/services/messagebus/MessageBusErrorUtils';

export default function messageBusErrorUtilsTest() {
  describe('messageBusErrorUtilsTest', () => {
    it('treats NetworkKit timeout code objects as timeouts', 0, () => {
      const info = parseMessageBusError({
        code: 2300028,
        message: 'request failed'
      });

      expect(info.code).assertEqual(2300028);
      expect(info.isTimeout).assertEqual(true);
      expect(info.text).assertContain('2300028');
    });
  });
}
