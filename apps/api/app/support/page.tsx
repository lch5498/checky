import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: '체키 지원',
  description: '체키 앱 사용 중 도움이 필요할 때 확인하는 지원 페이지입니다.',
  openGraph: {
    title: '체키 지원',
    description: '가족 일정과 주차 위치를 관리하는 체키의 도움말과 문의 안내입니다.',
    siteName: '체키',
    type: 'website',
    locale: 'ko_KR',
  },
};

const faqs = [
  {
    title: '가족을 먼저 만들어야 하나요?',
    description:
      '네. 체키는 가족 단위로 일정과 주차 정보를 관리합니다. 로그인 후 가족을 만들고 구성원을 등록하면 일정, 학교/학원, 주차 기능을 사용할 수 있습니다.',
  },
  {
    title: '학교/학원 일정은 캘린더에 자동 반영되나요?',
    description:
      '학교/학원에서 반복 일정을 등록하면 설정한 기간과 요일, 시간에 맞춰 캘린더 일정이 자동으로 생성됩니다.',
  },
  {
    title: '주차 위치는 가족끼리 공유되나요?',
    description:
      '같은 가족에 등록된 구성원은 차량별 주차 위치를 확인할 수 있습니다. 대표 권한을 가진 구성원은 차량과 즐겨찾는 위치를 관리할 수 있습니다.',
  },
  {
    title: '계정을 삭제할 수 있나요?',
    description:
      '앱의 프로필 화면에서 탈퇴하기를 선택하면 계정 삭제를 요청할 수 있습니다. 삭제된 데이터는 복구되지 않습니다.',
  },
];

export default function SupportPage() {
  return (
    <main className="support-shell">
      <section className="support-hero">
        <p className="eyebrow">체키 지원</p>
        <h1>무엇을 도와드릴까요?</h1>
        <p className="description">
          체키는 가족 일정, 학교·학원 반복 일정, 차량 주차 위치를 한곳에서
          관리할 수 있도록 돕는 가족 관리 앱입니다. 사용 중 문제가 있거나
          도움이 필요하면 아래 안내를 확인해 주세요.
        </p>
        <a
          className="support-button"
          href="https://github.com/lch5498/favis/issues"
          rel="noreferrer"
          target="_blank"
        >
          문의 남기기
        </a>
      </section>

      <section className="support-section" aria-labelledby="support-faq-title">
        <div className="support-section-header">
          <p className="label">도움말</p>
          <h2 id="support-faq-title">자주 묻는 질문</h2>
        </div>
        <div className="support-list">
          {faqs.map((faq) => (
            <article className="support-item" key={faq.title}>
              <h3>{faq.title}</h3>
              <p>{faq.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="support-section" aria-labelledby="support-privacy-title">
        <div className="support-section-header">
          <p className="label">개인정보</p>
          <h2 id="support-privacy-title">데이터와 권한 안내</h2>
        </div>
        <div className="support-list">
          <article className="support-item">
            <h3>로그인 정보</h3>
            <p>
              체키는 사용자 인증을 위해 카카오 로그인을 사용합니다. 앱 사용에
              필요한 최소한의 사용자 식별 정보만 저장합니다.
            </p>
          </article>
          <article className="support-item">
            <h3>연락처</h3>
            <p>
              학교·학원 전화번호 입력 시 기기의 연락처에서 번호를 선택할 수
              있습니다. 선택한 전화번호만 학교·학원 정보에 저장됩니다.
            </p>
          </article>
          <article className="support-item">
            <h3>계정 삭제</h3>
            <p>
              프로필 화면에서 로그아웃과 탈퇴를 진행할 수 있습니다. 탈퇴 시
              계정과 관련 데이터가 삭제되며 복구되지 않습니다.
            </p>
          </article>
          <article className="support-item">
            <h3>개인정보 처리방침</h3>
            <p>
              체키의 개인정보 수집, 이용, 보관, 삭제 기준은{' '}
              <a href="/privacy">개인정보 처리방침</a>에서 확인할 수 있습니다.
            </p>
          </article>
        </div>
      </section>
    </main>
  );
}
