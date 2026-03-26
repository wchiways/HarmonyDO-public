import localUnitTest from './LocalUnit.test';
import messageBusErrorUtilsTest from './MessageBusErrorUtils.test';

export default function testsuite() {
  localUnitTest();
  messageBusErrorUtilsTest();
}
