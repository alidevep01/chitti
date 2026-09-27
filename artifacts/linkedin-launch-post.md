# LinkedIn launch post — Chitti

I built something for my mom. ❤️

It is called **Chitti** — a private, invitation-only app that gives a family savings circle a simple digital home.

Chittis are built on trust, but running one can still mean keeping track of members, invitations, payout months, contributions, receipts, reminders, and changes across notebooks and messages. I wanted to make that work easier for my mom without changing the familiar way the family manages its money.

So I built an app around the complete workflow:

• An administrator creates a chitti, adds the members, and sets the contribution and schedule.

• Every member receives a unique private invitation that can be shared by email, WhatsApp, or the device share menu.

• The payout order is shuffled on the server. The result has an immutable hash, and every member must approve it. If someone rejects it, they can privately explain why to the administrator.

• Each month, members record a UPI or cash contribution and can attach a private payment-proof photo.

• The administrator independently verifies each payment, accepts or rejects it, and confirms the month's payout.

• The app calculates the schedule and final month, sends due and overdue reminders, keeps a private notification inbox, and generates payment-history and reliability reports.

It also handles the awkward real-life cases: late member joining and catch-up contributions, unpaid payout-month swaps, shared payout owners, edited invitations, importing an already-running chitti, historical records, and audited changes.

Importantly, **Chitti does not collect, hold, verify, or transfer money**. Payments still happen directly through UPI or cash. The app is the private record, coordination, and accountability layer around that process.

## How I built it

The frontend is written in **TypeScript** using **React 19, React Native, Expo, and Expo Router**. One responsive codebase powers the desktop web, mobile web, and future native Android/iOS builds.

The UI uses **React Native Paper**, with **React Hook Form + Zod** for validated forms, **TanStack Query** for server state, and **AsyncStorage** for the local demo experience.

The backend is built on **Supabase**:

• PostgreSQL for the data model

• Google OAuth for authentication

• Row Level Security for per-user privacy

• Transactional database functions for critical workflows

• Realtime-ready notifications

• Storage for avatars and private payment proofs

• Edge Functions + Web Push for privacy-safe notifications

• Scheduled database jobs for daily payment reminders

The database also keeps append-only audit events, enforces state transitions and financial values server-side, and stores amounts as integer paise to avoid floating-point errors.

For reliability, I added TypeScript checks, ESLint, Vitest unit tests, and PostgreSQL integration tests for invitation redemption, shuffling, late joining, payment review, shared payouts, month swaps, imports, reminders, reports, and cancellation flows.

Chitti works in a browser on desktop and mobile. It is also a **Progressive Web App (PWA)**, so it can be installed from the browser onto a computer or phone and opened like a regular app. The same Expo project is ready to produce native Android and iOS builds later; it is not currently an App Store or Play Store release.

You can see it here: **https://mychitti.expo.app**

This started as a project for my mom, but it became a lesson in designing software around trust, privacy, accountability, and the messy edge cases of real family workflows.

I would love to hear your feedback — especially from anyone who has helped run a family chitti or built software for the people closest to them.

#BuildInPublic #TypeScript #ReactNative #Expo #Supabase #PWA #FamilyTech

---

# Shorter LinkedIn version

I built something for my mom. ❤️

It is called **Chitti** — a private, invitation-only app for managing a family savings circle.

It brings the full workflow into one place: creating a chitti, inviting members, securely shuffling and approving the payout order, tracking monthly UPI/cash contributions, uploading payment proofs, confirming payouts, sending reminders, and generating member reports.

I also designed it for the situations that happen in real life: late members, catch-up contributions, payout-month swaps, shared payouts, edited invitations, existing-chitti imports, historical records, and audited changes.

Chitti does **not** collect or transfer money. Payments continue to happen directly through UPI or cash; the app provides the private record and coordination layer.

**Stack:** TypeScript, React 19, React Native, Expo, Expo Router, React Native Paper, TanStack Query, React Hook Form, Zod, Supabase/PostgreSQL, Google OAuth, Row Level Security, Storage, Edge Functions, Realtime, Web Push, and scheduled reminders.

It works on desktop and mobile web, and because it is a PWA, it can be installed on a phone or computer and opened like an app. The shared Expo codebase is also ready for future native Android and iOS builds.

Try it here: **https://mychitti.expo.app**

Building this for my mom reminded me that some of the most meaningful software starts with one person you care about.

I would love your feedback.

#BuildInPublic #TypeScript #ReactNative #Expo #Supabase #PWA #FamilyTech

---

# 90-second video script and shot list

## 0–8 seconds — Personal opening

**Say:**

“I built an app for my mom. It is called Chitti, and it helps a family manage a private savings circle from start to finish.”

**Show:** The Chitti icon, followed by the landing or sign-in screen.

## 8–25 seconds — The problem

**Say:**

“Managing a chitti can mean tracking members, payout months, contributions, reminders, and receipts across notebooks and messages. I wanted to give that entire workflow one simple, private home.”

**Show:** The administrator dashboard and a chitti overview.

## 25–50 seconds — Main workflow

**Say:**

“The administrator creates the chitti and sends each member a private invitation. The payout order is shuffled on the server, and every member can approve it or privately explain a rejection. Each month, members record a UPI or cash payment and can add a receipt. The administrator verifies it and confirms the payout.”

**Show:** Create-chitti flow, invitation card, shuffle screen, approval screen, then payment submission.

## 50–65 seconds — Real-life details

**Say:**

“It also handles reminders, payment reports, late members, catch-up payments, payout-month swaps, shared payouts, imported existing chittis, and a complete audit history.”

**Show:** Notifications, reports, member reliability, and activity history.

## 65–80 seconds — Stack and platforms

**Say:**

“I built it with TypeScript, React Native, Expo, Expo Router, and Supabase. PostgreSQL, Row Level Security, transactional server functions, private storage, realtime data, scheduled jobs, and Web Push power the backend.”

**Show:** A quick architecture graphic or brief code/database clips, then the app side-by-side on desktop and mobile.

## 80–90 seconds — Important boundary and close

**Say:**

“Chitti never handles the money itself; UPI and cash stay outside the app. It is the private coordination and record layer. It works in the browser and can be installed as a PWA on a phone or computer. You can try it at mychitti.expo.app. I would love your feedback.”

**Show:** Install-app prompt, Chitti icon, and the URL: https://mychitti.expo.app

---

# Suggested LinkedIn upload

1. Upload `assets/icon.png` as the first image if you are making an icon-only post.
2. For a video post, use the icon as the opening and closing card, and put `https://mychitti.expo.app` on the closing frame.
3. Use the shorter post as the video caption. Use the longer post when publishing without a video.
