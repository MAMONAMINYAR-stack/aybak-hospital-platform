# 03 — Development Report | گزارش توسعه (اجنت ۳)

- **Input / ورودی:** فقط `handoff/02-repair.md` (بخش «باقی‌مانده» L-01..L-07)
- **Branch / برنچ:** `arena/90bc4b95-aybak-hospital-platform` (طبق تأیید مرحله ۰؛ معادل `feat/…`)
- **Delivery / تحویل:** فقط از طریق PR به `main` — merge با کاربر است.
- **Date / تاریخ:** 2026-11-05

## English summary

All seven leftovers from the repair report were developed: Vitest + Testing Library setup (L-01), GitHub Actions CI (L-02), modular refactor of the 545-line monolith into `auth/`, `components/`, `data/`, `pages/` with behavior preserved (L-03), honest demo-action feedback + localStorage-persisted non-sensitive settings (L-04), error boundary (L-05), accessible nav (L-06), and separation of synthetic data with explicit DEMO labels — clinical values unchanged and locked by a test (L-07). **22 tests / 6 files, all green; build passes.** No clinical/legal change was executed.

## ماژول‌های توسعه‌یافته + معیار پذیرش

### M-01 زیرساخت تست (L-01)
- **فایل‌ها:** `package.json` (اسکریپت‌های `test`, `test:watch` + devDeps: vitest 3.2.7، jsdom 30، @testing-library/react 16، jest-dom 7، user-event 14)، `vite.config.js` (بخش `test`)، `src/test/setup.js`.
- **معیار پذیرش:** `npm test` اجرا و سبز شود؛ cleanup و پاک‌سازی localStorage/history بین تست‌ها. ✅ برآورده شد.

### M-02 CI (L-02)
- **فایل‌ها:** `.github/workflows/ci.yml` — روی هر PR و push به main: `npm ci` → `npm run build` → `npm test` (Node 22، کش npm).
- **معیار پذیرش:** workflow معتبر با نصب تکرارپذیر؛ اجرا روی همین PR. ✅ ساخته شد (اجرای واقعی روی GitHub پس از push).

### M-03 رفکتور ماژولار با حفظ رفتار (L-03)
- **فایل‌ها:** `src/App.jsx` (فقط routing + providers)، `src/auth/DemoAuthContext.jsx`، `src/components/ProtectedLayout.jsx`، `src/pages/{Login,Dashboard,Appointments,Patients,Prescriptions,Settings}Page.jsx`.
- **معیار پذیرش:** همه مسیرهای قبلی (`/login`, `/`, `/appointments`, `/patients`, `/prescriptions`, `/settings`, catch-all) و منطق محافظت‌شده حفظ شوند؛ ورود با هر مقدار غیرخالی و رد خالی؛ logout؛ UI یکسان. ✅ با ۷ تست یکپارچه در `src/App.test.jsx` و ۴ تست واحد auth اثبات شد.

### M-04 بازخورد دمو + ترجیحات پایدار (L-04)
- **فایل‌ها:** `src/components/DemoActionButton.jsx` (Export، + New Booking، Add Patient، + New Prescription، Forgot password)، `src/pages/SettingsPage.jsx` (ذخیره در localStorage با کلید `aybak.demo.notificationPrefs.v1`).
- **معیار پذیرش:** کلیک → پیام `role="status"` «Demo only — no data was changed.» و محو خودکار؛ ترجیحات پس از remount حفظ شوند؛ storage خراب کرش نکند؛ هیچ رمز/داده بیمار ذخیره نشود. ✅ با ۶ تست اثبات شد.

### M-05 ErrorBoundary (L-05)
- **فایل‌ها:** `src/components/ErrorBoundary.jsx` + پیچش کل App.
- **معیار پذیرش:** خطای رندر → fallback خوانا با دکمه Reload به‌جای صفحه سفید؛ بدون telemetry خارجی. ✅ با ۲ تست اثبات شد.

### M-06 دسترس‌پذیری ناوبری (L-06)
- **فایل‌ها:** `src/components/ProtectedLayout.jsx` — `aria-label="Main navigation"`.
- **معیار پذیرش:** nav با نام دسترس‌پذیر قابل انتخاب باشد. ✅ در تست ناوبری assert شد.

### M-07 جداسازی داده دمو با برچسب (L-07)
- **فایل‌ها:** `src/data/demoData.js` (انتقال عین مقادیر)، بنر DEMO در layout و صفحات Patients/Prescriptions.
- **معیار پذیرش:** `IS_DEMO_DATA=true`؛ متن «Synthetic demo data — not real patient records. Not for clinical use.»؛ **مقادیر دارو/دوز دقیقاً برابر نسخه قبل** (تست قفل‌کننده مقادیر). ✅ با ۳ تست اثبات شد.

## تست‌ها و نتایج

```
✓ src/App.test.jsx                      (7 tests)  — routing, demo login/logout, guards, nav, no hardcoded creds
✓ src/pages/SettingsPage.test.jsx       (4 tests)  — defaults, persistence, corrupted storage, no sensitive data
✓ src/data/demoData.test.js             (3 tests)  — DEMO flags, clinical values unchanged, schema/counts
✓ src/auth/DemoAuthContext.test.jsx     (4 tests)  — initial state, empty rejected, login/logout, provider guard
✓ src/components/DemoActionButton.test.jsx (2)     — notice appears, auto-hides
✓ src/components/ErrorBoundary.test.jsx (2 tests)  — healthy render, fallback on crash

Test Files  6 passed (6) | Tests  22 passed (22) | Duration ~6.6s
```

## فهرست PRها

- **PR #64:** https://github.com/MAMONAMINYAR-stack/aybak-hospital-platform/pull/64 — از `arena/90bc4b95-aybak-hospital-platform` به `main`؛ شامل هر ۴ مرحله با کامیت‌های جداگانه (محدودیت تک‌برنچی Arena، تأییدشده در مرحله ۰).
- merge فقط توسط کاربر.

## باقی‌مانده

- ~~اجرای واقعی CI روی GitHub~~ → انجام شد؛ به «پیگیری CI» در شواهد اجرا مراجعه کنید.
- تصمیم درباره ارتقای شکسته Vite 5→8 (آسیب‌پذیری dev-server؛ در «نیازمند تأیید» 02-repair).
- پیشنهادهای ساختاری اجنت ۴ (فقط پیشنهاد — اجرا منوط به تأیید).
- ارتقای actions به v5 (اعلان deprecation: اکشن‌های v4 روی Node 20 هدف‌گذاری شده‌اند و runner آن‌ها را با Node 24 اجرا می‌کند — فقط notice، CI سبز است).

## نیازمند تأیید (اجرا نشد — مطابق 01/02)

1. احراز هویت واقعی، نشست، Remember me/Forgot password واقعی.
2. داده واقعی بیمار (PHI)، بک‌اند، رضایت‌نامه، audit log.
3. منطق بالینی نسخه‌ها؛ مقادیر دمو دست‌نخورده و با تست قفل شده‌اند.
4. LICENSE، سلب مسئولیت پزشکی، بومی‌سازی UI (فارسی/RTL).

## شواهد اجرا

```
$ npm install -D vitest@^3 jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event
  → added 97 packages ✅
$ npm test        → 6 files / 22 tests passed ✅
$ npm run build   → ✓ built in 1.28s (dist/assets/index-DMLJC7zP.js 204.06 kB) ✅
```

### پیگیری CI (پس از push)

1. **Run 41899818636 — failure در «Set up job»:** طبق annotation گیت‌هاب، سیاست مخزن اجازه نمی‌دهد اکشن‌ها با tag استفاده شوند: «all actions must be pinned to a full-length commit SHA».
2. **ترمیم (کامیت `640ced1`):** `actions/checkout@11d5960a…` (v4) و `actions/setup-node@49933ea5…` (v4) به SHA کامل pin شدند؛ runner به `ubuntu-24.04` مقید شد.
3. **Run 41900016964 — ✅ success:** همه stepها سبز (Checkout → Setup Node → npm ci → Build → Test → Complete job). تنها annotation باقی‌مانده: notice مربوط به Node 20 در اکشن‌های v4 (غیرمسدودکننده؛ در باقی‌مانده ثبت شد).
