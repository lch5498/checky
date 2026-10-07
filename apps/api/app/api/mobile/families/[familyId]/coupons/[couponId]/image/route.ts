import { couponImageResponse } from '../../../../../../../../src/coupons';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
import { jsonFromError } from '../../../../../../../../src/http';

export const runtime = 'nodejs';
export async function GET(request: Request, context: { params: Promise<{ familyId: string; couponId: string }> }) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, couponId } = await context.params;
    return await couponImageResponse(userId, familyId, couponId);
  } catch (e) { return jsonFromError(e, 'coupon_image_fetch_failed'); }
}
