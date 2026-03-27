import localUnitTest from './LocalUnit.test';
import messageBusErrorUtilsTest from './MessageBusErrorUtils.test';
import topicListFabModeUtilsTest from './TopicListFabModeUtils.test';
import inviteLinksPageUtilsTest from './InviteLinksPageUtils.test';
import openSourceInfoContractTest from './OpenSourceInfoContract.test';

export default function testsuite() {
  localUnitTest();
  messageBusErrorUtilsTest();
  topicListFabModeUtilsTest();
  inviteLinksPageUtilsTest();
  openSourceInfoContractTest();
}
