import { TimeUtils } from '../common/utils/TimeUtils';

/**
 * 邀请链接详情
 */
export class InviteLinkDetails {
  id: number | null = null;
  inviteKey: string | null = null;
  maxRedemptionsAllowed: number | null = null;
  redemptionCount: number | null = null;
  expired: boolean | null = null;
  createdAt: Date | null = null;
  expiresAt: Date | null = null;

  static fromJson(json: Record<string, Object>): InviteLinkDetails {
    const d: InviteLinkDetails = new InviteLinkDetails();

    const idVal = json['id'];
    d.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : null;

    const keyVal = json['invite_key'];
    d.inviteKey = keyVal !== undefined && keyVal !== null ? keyVal as string : null;

    const maxVal = json['max_redemptions_allowed'];
    d.maxRedemptionsAllowed = maxVal !== undefined && maxVal !== null ? Number(maxVal.toString()) : null;

    const usedVal = json['redemption_count'];
    d.redemptionCount = usedVal !== undefined && usedVal !== null ? Number(usedVal.toString()) : null;

    const expiredVal = json['expired'];
    d.expired = expiredVal !== undefined && expiredVal !== null ? expiredVal as boolean : null;

    const createdVal = json['created_at'];
    d.createdAt = createdVal !== undefined && createdVal !== null ? TimeUtils.parseUtcTime(createdVal as string) : null;

    const expiresVal = json['expires_at'];
    d.expiresAt = expiresVal !== undefined && expiresVal !== null ? TimeUtils.parseUtcTime(expiresVal as string) : null;

    return d;
  }
}

/**
 * 邀请链接响应
 */
export class InviteLinkResponse {
  inviteLink: string = '';
  invite: InviteLinkDetails | null = null;

  static fromJson(json: Record<string, Object>): InviteLinkResponse {
    const resp: InviteLinkResponse = new InviteLinkResponse();

    const linkVal = json['invite_link']
      ?? json['invite_url']
      ?? json['url']
      ?? json['link'];
    resp.inviteLink = linkVal !== undefined && linkVal !== null ? linkVal as string : '';

    const inviteVal = json['invite'];
    if (inviteVal !== undefined && inviteVal !== null && typeof inviteVal === 'object') {
      resp.invite = InviteLinkDetails.fromJson(inviteVal as Record<string, Object>);
    } else if (json['invite_key'] !== undefined
      || json['expires_at'] !== undefined
      || json['max_redemptions_allowed'] !== undefined) {
      resp.invite = InviteLinkDetails.fromJson(json);
    }

    return resp;
  }
}
