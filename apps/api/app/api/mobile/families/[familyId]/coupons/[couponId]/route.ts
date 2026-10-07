import { deleteCoupon, getCoupon, updateCoupon } from '../../../../../../../src/coupons';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';
import { jsonFromError } from '../../../../../../../src/http';

export const runtime = 'nodejs';
type Context = { params: Promise<{ familyId: string; couponId: string }> };
export async function GET(request: Request, context: Context) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, couponId } = await context.params;
    return Response.json(await getCoupon(userId, familyId, couponId), { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (e) { return jsonFromError(e, 'coupon_fetch_failed'); }
}
export async function PATCH(request: Request, context: Context) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, couponId } = await context.params;
    return Response.json(await updateCoupon(userId, familyId, couponId, request));
  } catch (e) { return jsonFromError(e, 'coupon_update_failed'); }
}
export async function DELETE(request: Request, context: Context) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, couponId } = await context.params;
    return Response.json(await deleteCoupon(userId, familyId, couponId, request));
  } catch (e) { return jsonFromError(e, 'coupon_delete_failed'); }
}
