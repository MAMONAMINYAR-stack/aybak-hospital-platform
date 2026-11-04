# AYBAK Hospital Platform

> ⚠️ **DEMO / نمونه نمایشی** — This app is a frontend-only demo with **synthetic data** and **no real authentication**. It is **not for clinical use**.
> این برنامه یک دموی صرفاً فرانت‌اند با **داده ساختگی** و **بدون احراز هویت واقعی** است و **برای استفاده بالینی نیست**.

## English

A multi-page doctor portal demo (dashboard, appointments, patients, prescriptions, settings) built with React 18, Vite, Tailwind CSS 4 and React Router 7.

### Quick start

```bash
npm ci        # reproducible install (lockfile committed)
npm run dev   # dev server on http://localhost:5173
npm run build # production build → dist/
npm test      # unit/integration tests (Vitest + Testing Library)
```

**Demo login:** any non-empty email + password signs you in. No credentials are stored or checked — real authentication is on the roadmap and requires approval (see `handoff/`).

### Project structure

```
src/
  App.jsx            # routes + providers
  auth/              # demo auth context (in-memory only)
  components/        # shared UI (layout, error boundary, demo actions)
  data/              # synthetic DEMO data — never real patient data
  pages/             # one module per screen
  test/              # test setup
handoff/             # staged agent reports: audit → repair → development → organization
.github/workflows/   # CI: install, build, test
```

### Safety rules

- No real patient data (PHI) or secrets in this repository — synthetic, labeled demo data only.
- Clinical/legal changes (real auth, PHI handling, prescription logic, licensing) are **proposal-only** until approved; see the «نیازمند تأیید» sections in `handoff/`.
- `main` is never modified directly by agents; all changes arrive via PR and are merged by the maintainer.

## فارسی

دموی پرتال پزشک چندصفحه‌ای (داشبورد، نوبت‌ها، بیماران، نسخه‌ها، تنظیمات) با React 18، Vite، Tailwind CSS 4 و React Router 7.

### شروع سریع

```bash
npm ci        # نصب تکرارپذیر (lockfile در مخزن ثبت شده)
npm run dev   # سرور توسعه روی http://localhost:5173
npm run build # خروجی پروداکشن در dist/
npm test      # تست‌های واحد/یکپارچه (Vitest + Testing Library)
```

**ورود دمو:** هر ایمیل و رمز غیرخالی وارد می‌شود؛ هیچ اعتبارنامه‌ای ذخیره یا بررسی نمی‌شود. احراز هویت واقعی در نقشه راه است و نیازمند تأیید (به `handoff/` مراجعه کنید).

### قواعد ایمنی

- هیچ داده واقعی بیمار (PHI) یا secret در این مخزن نیست — فقط داده ساختگیِ برچسب‌خورده DEMO.
- تغییرات بالینی/حقوقی (احراز هویت واقعی، داده بیمار، منطق نسخه، لایسنس) تا تأیید کاربر **فقط پیشنهاد** می‌شوند؛ بخش‌های «نیازمند تأیید» در `handoff/`.
- هیچ اجنتی مستقیم روی `main` نمی‌نویسد؛ همه تغییرات از طریق PR و merge توسط نگهدارنده است.

## Process documents / مستندات فرایند

| File | Content |
|------|---------|
| `handoff/00-stage0.md` | Safety rules, Stage-0 decisions, agent prompts |
| `handoff/01-audit.md` | Evidence-based audit (Agent 1) |
| `handoff/02-repair.md` | Repairs, leftovers, needs-approval (Agent 2) |
| `handoff/03-development.md` | Modules, tests, acceptance criteria (Agent 3) |
| `handoff/04-organization.md` | Structure proposals — no deletions (Agent 4) |

**License:** undecided — requires maintainer approval (see `handoff/01-audit.md` F-12).
