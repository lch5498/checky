import type { Metadata } from 'next';

type InvitePageProps = {
  params: Promise<{
    inviteToken: string;
  }>;
};

export const metadata: Metadata = {
  title: '체키 그룹 초대',
  description: '체키에서 그룹 일정과 주차 위치를 함께 관리해요.',
  openGraph: {
    title: '체키 그룹 초대',
    description: '체키에서 그룹 일정과 주차 위치를 함께 관리해요.',
    siteName: '체키',
    type: 'website',
    locale: 'ko_KR',
  },
  twitter: {
    card: 'summary',
    title: '체키 그룹 초대',
    description: '체키에서 그룹 일정과 주차 위치를 함께 관리해요.',
  },
};

export default async function InvitePage({ params }: InvitePageProps) {
  const { inviteToken } = await params;
  const safeInviteToken = encodeURIComponent(inviteToken);
  const appUrl = `checky://family-invite/${safeInviteToken}`;

  return (
    <main className="invite-shell">
      <section className="invite-card">
        <div className="invite-icon">체키</div>
        <p className="eyebrow">그룹 초대</p>
        <h1>체키에서 초대를 열어주세요</h1>
        <p className="description">
          그룹 일정과 주차 정보를 함께 관리할 수 있도록 체키 앱으로 이동합니다.
          앱이 열리지 않으면 아래 버튼을 눌러주세요.
        </p>
        <a className="primary-button" href={appUrl}>
          체키 앱에서 열기
        </a>
        <p className="invite-help">
          체키가 설치되어 있지 않다면 앱 설치 후 이 초대 링크를 다시 열어주세요.
        </p>
      </section>
      <script
        dangerouslySetInnerHTML={{
          __html: `window.setTimeout(function(){ window.location.href = ${JSON.stringify(appUrl)}; }, 350);`,
        }}
      />
    </main>
  );
}
