import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: '체키 개인정보 처리방침',
  description: '체키 앱의 개인정보 수집, 이용, 보관, 삭제에 대한 안내입니다.',
  openGraph: {
    title: '체키 개인정보 처리방침',
    description: '체키 앱의 개인정보 처리 기준과 이용자 권리를 안내합니다.',
    siteName: '체키',
    type: 'website',
    locale: 'ko_KR',
  },
};

const privacySections = [
  {
    title: '수집하는 개인정보',
    description:
      '체키는 카카오 또는 Apple 로그인을 통한 사용자 식별 정보, 앱에서 사용자가 직접 입력한 닉네임, 그룹 및 구성원 정보, 일정, 기념일, 차량 및 주차 위치, 반복 일정 정보와 전화번호를 서비스 제공에 필요한 범위에서 저장합니다.',
  },
  {
    title: '개인정보 이용 목적',
    description:
      '수집한 정보는 로그인 상태 유지, 그룹 단위 데이터 관리, 일정 및 주차 위치 공유, 기념일 표시, 반복 일정 정보 관리, 고객 문의 대응, 서비스 안정성 개선을 위해 사용합니다.',
  },
  {
    title: '연락처 접근',
    description:
      '반복 일정 전화번호 입력 시 사용자가 선택한 경우에만 기기의 연락처를 불러올 수 있습니다. 연락처 전체를 서버에 저장하지 않으며, 사용자가 선택한 전화번호만 반복 일정 정보에 저장됩니다.',
  },
  {
    title: '제3자 제공',
    description:
      '체키는 법령에 따른 요청이 있거나 사용자가 명시적으로 동의한 경우를 제외하고 개인정보를 제3자에게 판매하거나 제공하지 않습니다. 사용자 인증에는 카카오 및 Apple 로그인을 사용할 수 있습니다.',
  },
  {
    title: '보관 및 삭제',
    description:
      '개인정보는 서비스 이용 기간 동안 보관됩니다. 사용자는 앱의 프로필 화면에서 탈퇴를 요청할 수 있으며, 탈퇴 시 계정과 관련 데이터는 삭제되고 복구되지 않습니다. 자세한 삭제 방법은 계정 삭제 안내 페이지에서 확인할 수 있습니다.',
  },
  {
    title: '보안',
    description:
      '체키는 개인정보를 보호하기 위해 접근 권한을 제한하고, 서비스 운영에 필요한 범위에서만 데이터를 처리합니다. 다만 인터넷 기반 서비스 특성상 절대적인 보안을 보장할 수는 없습니다.',
  },
  {
    title: '문의',
    description:
      '개인정보와 관련한 문의는 지원 페이지 또는 GitHub 이슈를 통해 남겨 주세요. 접수된 문의는 확인 후 가능한 한 빠르게 답변하겠습니다.',
  },
];

export default function PrivacyPage() {
  return (
    <main className="support-shell">
      <section className="support-hero">
        <p className="eyebrow">개인정보 처리방침</p>
        <h1>체키 개인정보 처리방침</h1>
        <p className="description">
          체키는 사용자가 입력한 일정, 주차 위치, 기념일, 구성원 정보를 안전하게
          관리하기 위해 필요한 최소한의 개인정보를 처리합니다. 이 문서는 체키가
          어떤 정보를 어떤 목적으로 사용하는지 안내합니다.
        </p>
        <p className="privacy-updated">시행일: 2026년 7월 3일</p>
      </section>

      <section className="support-section" aria-labelledby="privacy-list-title">
        <div className="support-section-header">
          <p className="label">정책 안내</p>
          <h2 id="privacy-list-title">개인정보 처리 기준</h2>
        </div>
        <div className="support-list">
          {privacySections.map((section) => (
            <article className="support-item" key={section.title}>
              <h3>{section.title}</h3>
              <p>{section.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="support-section" aria-labelledby="privacy-contact-title">
        <div className="support-section-header">
          <p className="label">문의</p>
          <h2 id="privacy-contact-title">도움이 필요하신가요?</h2>
        </div>
        <div className="support-list">
          <article className="support-item">
            <h3>지원 페이지</h3>
            <p>
              앱 사용 및 개인정보 관련 문의는{' '}
              <a href="/support">체키 지원 페이지</a>에서 확인하거나 문의를 남겨
              주세요. 계정 및 데이터 삭제 방법은{' '}
              <a href="/account-deletion">계정 삭제 안내</a>에서 확인할 수 있습니다.
            </p>
          </article>
        </div>
      </section>
    </main>
  );
}
