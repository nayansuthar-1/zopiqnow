# ZOPIQNOW — Software Architecture & Implementation Blueprint
### Unified Food + Grocery Q-Commerce Super-App
**Document Type:** Pre-Development Technical Blueprint (SAD)
**Version:** 1.0
**Status:** Baseline for Engineering Kickoff
**Scope:** Android-first (Flutter), web dashboards, backend, infra, ops, security, roadmap
**Audience:** Engineering, Product, DevOps, QA, Security, Founders/Investors

> **How to read this document:** This is the single source of architectural truth. Developers should not need to invent architecture — every decision, table, API order, and screen order is specified. Where a choice is deliberately deferred, it is marked `[DECISION-OWNER: CTO]`.

---

## Table of Contents
1. Product Vision
2. Complete Feature List (by module)
3. Applications Required
4. Technology Stack (2026)
5. Complete Database Design
6. Folder Structure
7. Flutter Architecture
8. Backend Architecture
9. Authentication & Authorization
10. Delivery Logic
11. Restaurant Features
12. Grocery Store Features
13. Customer Features
14. Delivery Partner Features
15. Admin Features
16. Support Dashboard
17. Payment System
18. Notification System
19. Maps
20. AI Features
21. Security
22. Performance
23. Testing Strategy
24. Deployment
25. Roadmap
26. Project Timeline
27. Risks
28. Future Features
29. Missing Features (Google-Architect Review)
30. Execution Deliverables (Dependency Graph, Implementation Orders, Checklists)

---
---

# SECTION 1 — PRODUCT VISION

## 1.1 Vision
> **"Anything you crave or need, at your door in minutes — one app for food, groceries, and daily essentials, powered by AI logistics."**

zopiqnow is a dual-vertical hyperlocal commerce platform combining **restaurant food delivery** (Zomato/Swiggy model) with **10–20 minute grocery/quick-commerce** (Blinkit/Zepto model) under a single customer identity, single cart-experience, single wallet, and shared delivery fleet.

## 1.2 Goals
| # | Goal | Metric (North Star) |
|---|------|---------------------|
| G1 | Unified food + grocery experience | 1 app, ≥2 verticals per active user/month |
| G2 | Sub-30-min food, sub-15-min grocery | Median delivery time |
| G3 | Marketplace liquidity | Orders/hour/dark-store; restaurants online |
| G4 | Unit-economics positive by Phase 4 | Contribution margin per order > 0 |
| G5 | Platform reliability at scale | 99.95% uptime, p95 API < 300ms |
| G6 | Fleet efficiency | Orders per rider-hour (batching) |

## 1.3 USP (Unique Selling Propositions)
1. **True single-cart cross-vertical checkout** — order biryani + milk + a phone charger in one checkout, delivered via optimally-batched riders.
2. **AI "Craving Engine"** — predicts what you want before you search (time-of-day + weather + history).
3. **Shared fleet & shared wallet** across food and grocery = lower delivery cost, higher rider utilization.
4. **Transparent live "kitchen + rider + store" tri-tracking.**
5. **Zero-surprise pricing** — all charges (taxes, surge, packaging) itemized before payment.
6. **Hyper-personalized dark-store assortment** driven by neighborhood demand prediction.

## 1.4 Revenue Model
| Stream | Description | Applies To |
|--------|-------------|-----------|
| Commission | 15–30% take rate | Restaurants, grocery brands |
| Delivery fee | Distance/weather/time based | Customer |
| Platform / handling fee | Flat per order | Customer |
| Surge / peak pricing | Dynamic multiplier | Customer |
| Subscription (zopiqPRO) | Free delivery + perks | Customer |
| Advertising / promoted listings | Sponsored ranking, banners | Vendors, brands |
| Private-label / dark-store margin | Owned inventory markup | Grocery |
| Packaging & convenience fee | Per order | Customer |
| Rider onboarding / gear | One-time | Delivery partners |
| Financial services (later) | BNPL, insurance, working-capital loans to vendors | Vendors, customers |
| Data & insights (aggregate, anonymized) | Market reports | Brands (B2B) |

## 1.5 Business Model
- **Marketplace** (restaurants + 3P grocery sellers) — asset-light.
- **1P Dark Stores** (owned inventory, q-commerce) — asset-heavy, higher margin.
- **Hybrid fleet:** owned/leased riders + gig riders + 3P logistics overflow.
- **Two-sided network:** supply (vendors/riders) ↔ demand (customers), balanced by incentives + surge.

## 1.6 Future Expansion
Medicine/pharmacy, pet supplies, cloud kitchens, print/stationery, alcohol (licensed geos), corporate/B2B catering, scheduled subscriptions (milk/newspaper), international multi-currency/multi-language, drone & EV fleet, "zopiq Mall" (electronics/fashion long-tail), fintech (wallet → payments → lending).

---
---

# SECTION 2 — COMPLETE FEATURE LIST

**Legend:**
Priority: **P0** = MVP-critical, **P1** = launch, **P2** = post-launch, **P3** = future.
Complexity: **S** small, **M** medium, **L** large, **XL** very large.

## 2.1 Customer Module
| Feature | Purpose | Workflow (summary) | Dependencies | Pri | Cx |
|---|---|---|---|---|---|
| Onboarding/Signup | Acquire user | Phone OTP → profile → location | Auth, SMS OTP | P0 | M |
| Location & serviceability | Show only deliverable vendors | GPS/pin → geo-serviceability check | Maps, Geo service | P0 | M |
| Home feed (dual-vertical) | Discovery | Fetch personalized food+grocery rails | Catalog, Reco engine | P0 | L |
| Search (unified) | Find items/vendors | Query → search service → ranked results | Search engine | P0 | L |
| Restaurant listing/detail | Browse menus | Vendor → menu → item detail | Catalog | P0 | L |
| Grocery store/dark-store browse | Browse SKUs | Category → SKU grid → detail | Catalog, Inventory | P0 | L |
| Product/food detail | Convert | Variants/addons → add to cart | Cart | P0 | M |
| Cart (multi-vendor aware) | Hold selection | Add/update/remove; vertical rules | Pricing, Inventory | P0 | L |
| Checkout | Convert to order | Address+slot+pay+coupon → place | Orders, Payments | P0 | XL |
| Payments | Collect money | UPI/card/wallet/COD | Payment gateway | P0 | L |
| Live order tracking | Reduce anxiety | WS/poll rider+status+ETA | Maps, Realtime | P0 | L |
| Order history/reorder | Retention | List → reorder | Orders | P0 | S |
| Ratings & reviews | Quality signal | Rate order/item/rider | Reviews | P1 | M |
| Wallet | Payments + refunds | Balance, add, spend, refund | Wallet svc | P1 | M |
| Coupons/offers | Conversion | Apply at cart/checkout | Promo engine | P0 | M |
| Address book | Convenience | CRUD saved addresses | Geo | P0 | S |
| Favorites/wishlist | Retention | Save vendor/item | Catalog | P1 | S |
| zopiqPRO subscription | LTV | Buy → perks applied | Payments, Entitlements | P1 | M |
| Loyalty points | Retention | Earn/burn | Loyalty svc | P2 | M |
| In-app support/chat | CSAT | Ticket/chat/bot | Support | P1 | M |
| Notifications center | Engagement | Push/in-app list | Notif svc | P1 | S |
| Scheduled orders | Convenience | Pick slot → deferred order | Orders, Scheduler | P2 | M |
| Group ordering | AOV | Shared cart link | Cart, Realtime | P2 | L |
| Gift orders | New use case | Order to another address/phone | Orders | P2 | M |
| Referral | Growth | Share code → reward | Referral svc | P1 | M |
| Multi-language | Reach | i18n switch | Localization | P1 | M |
| Accessibility | Inclusion | Screen-reader/large text | Design system | P1 | M |
| Dietary/allergen filters | Trust | Filter feed/search | Catalog metadata | P2 | M |
| Reorder subscriptions (grocery) | Recurring rev | Auto-repeat cart on schedule | Scheduler, Payments | P3 | L |

## 2.2 Restaurant Module
| Feature | Purpose | Workflow | Dependencies | Pri | Cx |
|---|---|---|---|---|---|
| Restaurant onboarding/KYC | Supply | Docs → verify → go-live | Vendor verify | P0 | L |
| Menu management | Catalog | CRUD categories/items/addons/variants | Catalog | P0 | L |
| Availability toggle | Ops | Open/close, item in/out of stock | Catalog | P0 | S |
| Order inbox (accept/reject/ready) | Fulfillment | New order → accept → prep → ready | Orders, Realtime | P0 | L |
| Prep-time / auto-accept | SLA | Set prep time; auto-accept rules | Orders | P1 | M |
| Discounts/offers | Demand | Item/order level promos | Promo engine | P1 | M |
| Analytics dashboard | Insight | Sales, funnel, ratings | Analytics | P1 | L |
| Payouts & settlement | Trust | View earnings, settlement cycle | Finance | P0 | L |
| Tax & invoice | Compliance | GST/tax on invoices | Finance/Tax | P1 | M |
| Reports export | Ops | CSV/PDF | Reporting | P1 | M |
| Ratings response | Reputation | Reply to reviews | Reviews | P2 | S |
| Ads/promoted listing | Growth (their) | Buy placement | Ads svc | P2 | M |
| Multi-outlet management | Chains | Manage N branches | Org model | P2 | L |
| Printer/KOT integration | Kitchen ops | Print tickets | Device/print | P2 | M |
| Live order load / throttle | SLA protection | Pause new orders when busy | Orders | P1 | M |

## 2.3 Grocery Store / Dark-Store Module
| Feature | Purpose | Workflow | Dependencies | Pri | Cx |
|---|---|---|---|---|---|
| Store onboarding/KYC | Supply | Docs → verify | Vendor verify | P0 | L |
| Inventory management | Stock truth | CRUD SKU, stock in/out | Inventory | P0 | XL |
| Barcode / SKU scan | Speed/accuracy | Scan → identify → update | Inventory | P1 | M |
| Expiry & batch tracking | Compliance/waste | Batch, expiry alerts | Inventory | P1 | L |
| Variants/weight/unit | Catalog accuracy | 500g/1kg, pack sizes | Catalog | P0 | M |
| Pricing/MRP/margin | Revenue | Set price/MRP | Pricing | P0 | M |
| Combos/bundles | AOV | Bundle SKUs | Catalog/Promo | P1 | M |
| Flash sales | Demand | Time-boxed price | Promo | P2 | M |
| Picking & packing (in-store) | Fulfillment | Pick list → pack → handoff | Orders | P0 | L |
| Low-stock/reorder alerts | Availability | Threshold → alert/PO | Inventory | P1 | M |
| Purchase orders / supplier | Supply chain | Create PO, receive GRN | Supply chain | P2 | L |
| Store analytics | Insight | Fill rate, waste, sales | Analytics | P1 | L |
| Payouts/settlement | Trust | Earnings | Finance | P0 | L |

## 2.4 Delivery Partner Module
| Feature | Purpose | Workflow | Dependencies | Pri | Cx |
|---|---|---|---|---|---|
| Rider onboarding/KYC | Supply | Docs, vehicle, bank → verify | Vendor verify | P0 | L |
| Availability (online/offline) | Supply signal | Toggle duty | Dispatch | P0 | S |
| Order assignment/accept/reject | Fulfillment | Offer → accept → pickup → deliver | Dispatch, Realtime | P0 | XL |
| Turn-by-turn navigation | Efficiency | Route to pickup/drop | Maps | P0 | L |
| Batch/multi-drop | Efficiency | Sequence stops | Dispatch/route opt | P1 | XL |
| Earnings & incentives | Motivation | Per-order + surge + bonuses | Finance | P0 | L |
| Cash collection (COD) reconcile | Finance integrity | Collect → owe → settle | Finance | P0 | L |
| Heat map / demand zones | Utilization | Show high-demand areas | Analytics/Maps | P1 | M |
| Wallet & instant payout | Motivation | Withdraw earnings | Finance/Payments | P1 | M |
| Ratings & performance | Quality | Score, tiers | Reviews | P1 | M |
| SOS / safety | Safety | Panic button, share trip | Safety svc | P1 | M |
| Proof of delivery | Dispute prevention | OTP/photo/signature | Orders | P0 | M |
| Break / shift management | Ops | Scheduled shifts (owned fleet) | Workforce | P2 | M |

## 2.5 Admin Module
| Feature | Purpose | Pri | Cx |
|---|---|---|---|
| Global order management/override | Ops control | P0 | L |
| Vendor verification & lifecycle | Supply integrity | P0 | L |
| Rider verification & lifecycle | Supply integrity | P0 | L |
| Catalog moderation | Quality | P1 | L |
| Pricing/commission config | Revenue | P0 | L |
| Coupon/promo management | Growth | P0 | L |
| Payments/refunds/settlements | Finance | P0 | XL |
| CMS (banners, pages, config) | Merchandising | P1 | L |
| Push/marketing campaigns | Engagement | P1 | L |
| User management & fraud actions | Trust/safety | P0 | L |
| Reports/analytics/revenue | Insight | P1 | XL |
| Tax configuration | Compliance | P1 | L |
| Geo/zone/serviceability config | Ops | P0 | L |
| Surge & delivery-fee rules | Revenue/ops | P0 | L |
| Feature flags / remote config | Release control | P1 | M |
| Audit log viewer | Compliance/security | P1 | M |

## 2.6 Super Admin Module
| Feature | Purpose | Pri | Cx |
|---|---|---|---|
| Admin/role/permission management (RBAC) | Governance | P0 | L |
| Multi-region / multi-tenant config | Expansion | P2 | XL |
| System-wide financial ledger view | Finance oversight | P1 | XL |
| Kill-switch / maintenance mode | Incident control | P0 | M |
| Data governance / PII access control | Compliance | P1 | L |
| Global config & environment mgmt | Ops | P1 | M |
| Impersonation (audited) | Support/debug | P1 | M |
| Compliance & legal exports (GDPR/DPDP) | Legal | P1 | L |

## 2.7 Support Team Module
| Feature | Purpose | Pri | Cx |
|---|---|---|---|
| Ticket queue & assignment | Triage | P0 | L |
| Live chat (customer/vendor/rider) | Resolution | P1 | L |
| Voice/call integration & logs | Resolution | P2 | M |
| Order lookup & 360° context | Efficiency | P0 | L |
| Refund/compensation issuance (bounded) | Resolution | P0 | L |
| Escalation & SLA tracking | Quality | P1 | M |
| Canned responses / macros | Efficiency | P1 | S |
| Knowledge base | Deflection | P1 | M |
| CSAT collection | Quality | P1 | S |

---
---

# SECTION 3 — APPLICATIONS REQUIRED

| # | Application | Platform | Primary Users | Pri |
|---|---|---|---|---|
| A1 | Customer App | Flutter (Android first, iOS-ready) | Customers | P0 |
| A2 | Restaurant Partner App | Flutter (Android/tablet) | Restaurants | P0 |
| A3 | Grocery/Dark-Store App | Flutter (Android/tablet, scanner support) | Store staff | P0 |
| A4 | Delivery Partner App | Flutter (Android) | Riders | P0 |
| A5 | Admin Web Panel | React (web) | Ops/Admin | P0 |
| A6 | Super Admin Console | React (web, hardened) | Super admins | P1 |
| A7 | Support Dashboard | React (web) | Support agents | P1 |
| A8 | Analytics/BI Dashboard | Metabase/Superset + custom | Leadership, ops | P1 |
| A9 | Marketing/Growth Dashboard | React module | Marketing | P1 |
| A10 | Finance/Settlement Dashboard | React module | Finance | P1 |
| A11 | CMS (banners/pages/config) | React module | Merchandising | P1 |
| A12 | Internal Ops / Dispatch Control Tower | React (real-time map) | Ops/logistics | P1 |
| A13 | Vendor Verification Portal | React module | Onboarding team | P1 |
| A14 | Customer Web (PWA, ordering) | React/Next.js | Customers | P2 |
| A15 | Vendor Web Portal (menu/analytics on desktop) | React | Vendors | P2 |
| A16 | Rider Web (earnings/statements) | React | Riders | P3 |
| A17 | Public Marketing Website | Next.js (SEO) | Prospects | P1 |
| A18 | Status Page | Hosted (Statuspage/Instatus) | All | P2 |

> **Note:** A5–A13 are modules of **one** unified Admin Web platform with RBAC-gated navigation — not separate codebases. This reduces maintenance while presenting role-specific surfaces.

---
---

# SECTION 4 — TECHNOLOGY STACK (2026)

| Layer | Recommendation | Rationale |
|---|---|---|
| **Mobile Frontend** | Flutter 3.x (Dart 3), Material 3 | Single codebase Android+iOS; high perf; strong ecosystem |
| **Web Frontend** | React 18 + TypeScript + Vite; Next.js for public/SEO | Team velocity, ecosystem, SSR for marketing |
| **Web UI kit** | Tailwind + shadcn/ui (or MUI) | Consistent, fast |
| **Backend** | Node.js (NestJS, TypeScript) primary; Go for hot-path services (dispatch, location, search-gateway) | NestJS = structure/DI/velocity; Go = concurrency/latency |
| **API style** | REST (OpenAPI) + gRPC internal; GraphQL BFF for apps (optional) | REST public simplicity; gRPC low-latency internal; GraphQL flexible client fetch |
| **API Gateway** | Kong / Envoy (or AWS API Gateway) | Routing, auth, rate limit, observability |
| **Auth** | Keycloak or Auth0/Cognito; JWT (access) + rotating refresh; OTP via SMS | Standards-based, RBAC, social login |
| **Primary DB** | PostgreSQL 16 (transactional: orders, payments, users, catalog) | ACID, relational integrity, PostGIS geo |
| **Document/Flex DB** | MongoDB (catalog variants, CMS, flexible product attrs) | Schema flexibility for menu/SKU attributes |
| **Geo** | PostGIS + Redis Geo | Serviceability, nearest-driver |
| **Search** | Elasticsearch / OpenSearch (or Typesense for MVP) | Full-text, typo-tolerance, ranking, facets |
| **Cache** | Redis (cluster) | Sessions, hot catalog, rate-limit, geo, cart |
| **Object Storage** | AWS S3 (or GCS) | Images, docs, invoices |
| **CDN** | CloudFront / Cloudflare | Static + image delivery |
| **Image Optimization** | imgproxy / Cloudinary | On-the-fly resize/format (WebP/AVIF) |
| **Maps** | Google Maps Platform (Directions, Distance Matrix, Places, SDK); Mapbox as fallback/cost lever | Best coverage/accuracy in India |
| **Realtime** | WebSocket (Socket.IO / native) + Redis pub/sub; MQTT for rider location at scale | Live tracking, order status |
| **Queue / Streaming** | Apache Kafka (event backbone) + Redis/BullMQ (jobs) | Event-driven, decoupling, replay |
| **Background Jobs** | BullMQ (Node) / Temporal (workflows: settlement, refunds) | Reliable orchestration |
| **Notifications (Push)** | Firebase Cloud Messaging (FCM) | Android/iOS push |
| **SMS/OTP** | MSG91 / Twilio / AWS SNS (multi-provider failover) | Deliverability, redundancy |
| **Email** | AWS SES / SendGrid | Transactional + marketing |
| **WhatsApp** | Meta WhatsApp Business API (via Gupshup/Twilio) | High-open-rate updates |
| **Payments** | Razorpay (primary, India: UPI/cards/netbanking/wallet) + Stripe (intl); PayU as fallback | UPI-first, wide coverage |
| **Wallet ledger** | Internal double-entry ledger service (Postgres) | Financial integrity |
| **Analytics (product)** | Mixpanel/Amplitude + self-hosted event pipeline (Kafka→warehouse) | Funnels, retention |
| **Data Warehouse** | BigQuery / Snowflake / ClickHouse | BI, ML features |
| **BI** | Metabase / Superset | Dashboards |
| **Crash Reporting** | Firebase Crashlytics + Sentry | Mobile + backend errors |
| **Monitoring** | Prometheus + Grafana; Datadog (managed alt) | Metrics/alerts |
| **Tracing** | OpenTelemetry + Jaeger/Tempo | Distributed tracing |
| **Logging** | ELK / Loki; structured JSON logs | Centralized logs |
| **Cloud** | AWS (primary) — EKS, RDS, ElastiCache, S3, MSK | Maturity, managed services |
| **Containers/Orchestration** | Docker + Kubernetes (EKS); Helm; ArgoCD (GitOps) | Scale, portability |
| **IaC** | Terraform | Reproducible infra |
| **CI/CD** | GitHub Actions + ArgoCD; Fastlane (mobile) | Automation |
| **Feature Flags/Remote Config** | Firebase Remote Config / Unleash | Safe rollout |
| **Secrets** | HashiCorp Vault / AWS Secrets Manager | Secure secrets |
| **AI/LLM** | Claude (Anthropic) API — chatbot, support automation, smart search NL, review summarization | Latest capable models (claude-opus-4-8 / claude-sonnet-5) |
| **Recommendation** | Feature store + ranking models (Vertex AI / SageMaker); vector DB (pgvector/Pinecone) | Personalization, semantic search |
| **Fraud Detection** | Rules engine + ML scoring (SageMaker); device fingerprint (FingerprintJS) | Reduce fraud losses |
| **Video Storage** | S3 + CloudFront; Mux (if reels/vendor video) | Vendor/marketing video |
| **Design/Docs** | Figma (design), Confluence/Notion (docs) | Collaboration |

---
---

# SECTION 5 — COMPLETE DATABASE DESIGN

> **Conventions:** All tables have `id UUID PK`, `created_at`, `updated_at`, `deleted_at` (soft delete where noted). Money stored as `BIGINT` minor units (paise) + `currency`. Enums explicit. FK = foreign key. Idx = index. Only representative fields shown for very large tables; full DDL to be generated from these specs in the data-modeling task.

## 5.1 Identity & Access
### `users`
| Field | Type | Notes |
|---|---|---|
| id | UUID PK | |
| phone | VARCHAR unique | E.164; primary login |
| email | VARCHAR unique nullable | |
| full_name | VARCHAR | |
| gender | ENUM nullable | |
| dob | DATE nullable | |
| avatar_url | TEXT nullable | |
| status | ENUM(active,blocked,deleted) | |
| referral_code | VARCHAR unique | |
| referred_by | UUID FK users nullable | |
| default_address_id | UUID FK addresses nullable | |
| locale | VARCHAR | i18n |
| fcm_tokens | JSONB | multi-device |
| flags | JSONB | risk/fraud/vip |
Idx: phone, email, referral_code, status.

### `roles`, `permissions`, `role_permissions`, `user_roles`
Standard RBAC. `roles(id, name, scope)`, `permissions(id, key, description)`, join tables. `user_roles(user_id, role_id, vendor_id nullable, region_id nullable)` — scoped roles.

### `admin_users` (separate hardened auth for staff), `admin_sessions`, `audit_logs`
`audit_logs(id, actor_id, actor_type, action, entity_type, entity_id, before JSONB, after JSONB, ip, ua, created_at)` — Idx: entity_type+entity_id, actor_id, created_at.

### `auth_sessions`
`(id, user_id, device_id, refresh_token_hash, expires_at, revoked, ip, user_agent)`.

### `otp_requests`
`(id, phone, code_hash, purpose ENUM, attempts, expires_at, verified_at)` — Idx: phone+purpose. Rate-limit tracked in Redis.

## 5.2 Location
### `addresses`
`(id, user_id FK, label ENUM(home,work,other), line1, line2, landmark, city, state, pincode, country, lat, lng, geohash, is_default, contact_name, contact_phone)`. Idx: user_id, geohash. PostGIS `geography(Point)`.

### `service_zones`
`(id, name, region_id, polygon geography(Polygon), vertical ENUM(food,grocery,both), active)`. Idx: GIST(polygon).

### `regions`, `cities`
Hierarchy for multi-region config.

## 5.3 Vendors (Restaurants + Stores)
### `vendors`
| Field | Type | Notes |
|---|---|---|
| id | UUID PK | |
| type | ENUM(restaurant, grocery, dark_store, pharmacy...) | |
| name, slug | | |
| owner_user_id | FK users | |
| org_id | FK vendor_orgs nullable | chains |
| status | ENUM(pending,under_review,active,suspended,rejected) | |
| lat,lng,geohash,address fields | | |
| service_zone_ids | JSONB | |
| commission_rate | NUMERIC | override of default |
| prep_time_default | INT | minutes |
| rating_avg, rating_count | | denormalized |
| is_open, open_hours | JSONB | schedule |
| gstin, fssai_no, licenses | | compliance |
| bank_account_id | FK | payouts |
| tags/cuisines | JSONB | |
Idx: type, status, geohash, slug.

### `vendor_orgs` (chains), `vendor_documents` (KYC docs + verification status), `vendor_bank_accounts`, `vendor_staff` (login accounts), `vendor_serviceability`, `vendor_working_hours`, `vendor_reviews_summary`.

## 5.4 Catalog
### `categories`
`(id, vendor_id nullable, parent_id, name, vertical, image_url, sort_order, is_global)` — supports global taxonomy + vendor-specific.

### `products` (grocery SKUs) / `menu_items` (food) — unified `catalog_items`
| Field | Type | Notes |
|---|---|---|
| id | UUID PK | |
| vendor_id | FK | |
| type | ENUM(food, grocery) | |
| category_id | FK | |
| name, description | | |
| images | JSONB | |
| base_price, mrp, tax_rate | | |
| is_veg | BOOL nullable | food |
| sku, barcode | | grocery |
| brand | | grocery |
| unit, weight, pack_size | | grocery |
| is_available | BOOL | |
| attributes | JSONB | allergens, spice, nutrition |
| rating_avg, rating_count | | |
| search_keywords | | |
Idx: vendor_id, category_id, sku, barcode, GIN(search).

### `item_variants` (size/weight/portion), `item_addons` & `addon_groups` (food: extra cheese, min/max rules), `combos`/`bundles`, `item_price_history`.

### `inventory` (grocery)
`(id, vendor_id, item_id, variant_id, quantity, reserved_qty, reorder_level, batch_no, expiry_date, cost_price, location_bin)`. Idx: vendor_id+item_id. Reservations on cart/checkout.

### `stock_history`
`(id, inventory_id, change_qty, reason ENUM(sale,restock,adjust,expiry,return), ref_order_id, actor_id, created_at)`.

### `purchase_orders`, `po_line_items`, `suppliers`, `grn` (goods received).

## 5.5 Cart & Orders
### `carts`
`(id, user_id, status ENUM(active,converted,abandoned), vertical_mix, applied_coupon_id, updated_at)`.
### `cart_items`
`(id, cart_id, vendor_id, item_id, variant_id, addons JSONB, qty, unit_price, notes)`.

### `orders`
| Field | Type | Notes |
|---|---|---|
| id | UUID PK | |
| order_no | VARCHAR unique | human-readable |
| user_id | FK | |
| type | ENUM(food, grocery, mixed) | |
| status | ENUM(created,confirmed,accepted,preparing,ready,picked_up,arriving,delivered,cancelled,refunded) | |
| sub_orders | via order_vendor rows | multi-vendor |
| address_id | FK | snapshot too |
| delivery_address_snapshot | JSONB | immutable |
| scheduled_slot | nullable | |
| items_total, tax_total, delivery_fee, packaging_fee, surge_amount, discount_total, tip, grand_total | money | |
| payment_status | ENUM(pending,paid,failed,refunded,partial) | |
| payment_method | ENUM | |
| coupon_id | FK nullable | |
| rider_id | FK nullable | |
| assigned_at, picked_at, delivered_at | | timestamps |
| eta, distance_km | | |
| cancellation_reason, cancelled_by | | |
| rating_id | FK nullable | |
Idx: user_id, status, rider_id, created_at, order_no.

### `order_vendors` (sub-order per vendor: vendor_id, status, prep_time, ready_at), `order_items` (snapshot of item+price+addons), `order_status_history` (id, order_id, status, actor, note, ts), `order_events` (audit).

### `delivery_tasks`
`(id, order_id, rider_id, sequence, type ENUM(pickup,drop), location, status, otp, proof_url, arrived_at, completed_at)` — supports batching/multi-drop.

## 5.6 Payments & Finance
### `payments`
`(id, order_id, user_id, gateway ENUM, gateway_txn_id, amount, currency, method, status ENUM(initiated,authorized,captured,failed,refunded), raw_response JSONB)`. Idx: order_id, gateway_txn_id.
### `refunds`
`(id, payment_id, order_id, amount, reason, status, gateway_refund_id, initiated_by, approved_by)`.
### `wallets` `(id, user_id/vendor_id/rider_id, owner_type, balance, currency, status)`.
### `wallet_transactions` (double-entry) `(id, wallet_id, type ENUM(credit,debit), amount, balance_after, ref_type, ref_id, description)`. Immutable ledger.
### `ledger_entries` (system double-entry) `(id, txn_group_id, account, debit, credit, currency, ref)`.
### `invoices` `(id, order_id/vendor_id, number, type ENUM(customer,vendor,rider), pdf_url, tax_breakup JSONB, total)`.
### `taxes` `(id, name, rate, type ENUM(GST,CGST,SGST,IGST,VAT), hsn_sac, applies_to)`.
### `commissions` `(id, vendor_id, category, rate, effective_from)`.
### `settlements` `(id, vendor_id/rider_id, period_start, period_end, gross, commission, deductions, tds, net_payable, status, payout_ref)`.
### `payouts` `(id, settlement_id, beneficiary, amount, method, status, utr, processed_at)`.
### `saved_cards`/`payment_methods` (tokenized; PCI — store gateway token only, never PAN).
### `cod_collections` `(id, order_id, rider_id, amount, collected_at, reconciled, deposit_ref)`.

## 5.7 Promotions & Loyalty
### `coupons` `(id, code, type ENUM(flat,percent,freedelivery,cashback), value, max_discount, min_order, usage_limit, per_user_limit, valid_from, valid_to, vertical, vendor_scope, first_order_only, status)`. Idx: code.
### `coupon_redemptions`, `offers` (vendor promos), `campaigns` (marketing), `banners` `(id, image, target, placement, vertical, priority, schedule, region)`, `ads`/`promoted_listings` `(id, vendor_id, item_id, bid, budget, placement, metrics)`.
### `loyalty_accounts`, `loyalty_transactions` (earn/burn), `subscriptions` `(id, user_id, plan_id, status, start, end, auto_renew)`, `subscription_plans`, `referrals` `(id, referrer_id, referee_id, status, reward_amount)`.

## 5.8 Reviews & Ratings
### `reviews` `(id, user_id, order_id, target_type ENUM(vendor,item,rider), target_id, rating INT, text, images JSONB, status ENUM(published,flagged,hidden), reply)`. Idx: target_type+target_id.
### `ratings_aggregate` (denormalized rollups).

## 5.9 Delivery / Fleet
### `riders` `(id, user_id, vehicle_type, vehicle_no, license_no, status ENUM(pending,active,suspended), current_status ENUM(online,offline,on_trip,break), rating, tier, bank_account_id, zone_id)`.
### `rider_documents` (KYC), `rider_locations` `(rider_id, lat, lng, heading, speed, accuracy, ts)` — high-write, use Redis Geo + time-series (ClickHouse/Timescale) not Postgres.
### `rider_shifts`, `rider_earnings` `(id, rider_id, order_id, base, distance_pay, surge, incentive, tip, total, date)`, `rider_incentives` (rules & payouts), `dispatch_offers` `(id, order_id, rider_id, status ENUM(offered,accepted,rejected,expired,timeout), offered_at, responded_at)`.

## 5.10 Support & Comms
### `support_tickets` `(id, user_id/vendor_id/rider_id, order_id nullable, category, priority, status, assigned_to, sla_due, resolution, csat)`.
### `ticket_messages`, `chat_threads`, `chat_messages` `(id, thread_id, sender_type, sender_id, body, attachments, read_at)`, `canned_responses`, `kb_articles`.
### `notifications` `(id, user_id, channel ENUM(push,sms,email,whatsapp,inapp), template_id, payload, status, sent_at, read_at)`, `notification_templates`, `notification_preferences`.

## 5.11 Platform / Config
### `feature_flags`, `remote_configs`, `app_versions` (force-update), `settings` (kv), `webhooks` (outbound to vendors), `api_keys`, `devices` `(id, user_id, device_id, platform, os, app_version, fcm_token, last_seen)`, `search_logs`, `events` (product analytics raw → warehouse).
### `favorites`/`wishlist` `(id, user_id, target_type, target_id)`, `recently_viewed`, `saved_searches`.

## 5.12 Relationship Summary (key FKs)
- users 1—N addresses, orders, reviews, wallets, tickets.
- vendors 1—N catalog_items, order_vendors, settlements, documents.
- orders 1—N order_items, order_vendors, delivery_tasks, payments; N—1 rider, coupon, address.
- riders 1—N delivery_tasks, rider_earnings, dispatch_offers.
- catalog_items 1—N variants, addons, inventory, reviews.

## 5.13 Indexing & Constraints Principles
- Composite indexes on hot query paths (e.g., `orders(user_id, status, created_at desc)`).
- Partial indexes (e.g., active vendors: `WHERE status='active'`).
- GIST for geo; GIN for JSONB/full-text.
- FK constraints ON DELETE RESTRICT for financial; soft-delete elsewhere.
- Unique constraints: phone, email, order_no, coupon code, gateway_txn_id, sku per vendor.
- Partitioning: `orders`, `rider_locations`, `events`, `wallet_transactions` by time (monthly) for scale.
- Check constraints: money ≥ 0 (except ledger), ratings 1–5.

---
---

# SECTION 6 — FOLDER STRUCTURE

## 6.1 Monorepo (recommended: Nx or Turborepo + Melos for Dart)
```
zopiqnow/
├── apps/
│   ├── mobile_customer/       # Flutter
│   ├── mobile_restaurant/     # Flutter
│   ├── mobile_grocery/        # Flutter
│   ├── mobile_rider/          # Flutter
│   ├── web_admin/             # React (Admin+Support+Finance+Marketing+CMS+Ops+Vendor-verify modules)
│   ├── web_customer/          # Next.js PWA
│   └── web_marketing/         # Next.js public site
├── services/                  # Backend microservices
│   ├── gateway/
│   ├── auth-service/
│   ├── user-service/
│   ├── vendor-service/
│   ├── catalog-service/
│   ├── inventory-service/
│   ├── cart-service/
│   ├── order-service/
│   ├── payment-service/
│   ├── wallet-ledger-service/
│   ├── promo-service/
│   ├── dispatch-service/      # Go
│   ├── location-service/      # Go
│   ├── search-service/
│   ├── notification-service/
│   ├── review-service/
│   ├── support-service/
│   ├── settlement-service/
│   ├── analytics-ingest/
│   ├── ai-service/            # LLM/reco/fraud orchestration
│   └── admin-bff/
├── packages/                  # Shared TS packages
│   ├── shared-types/          # OpenAPI-generated DTOs
│   ├── ui-web/                # React design system
│   ├── config/
│   └── sdk-client/
├── dart_packages/             # Shared Flutter packages (via Melos)
│   ├── zopiq_core/            # models, network, storage, DI
│   ├── zopiq_ui/              # design system, widgets, theme
│   ├── zopiq_auth/            # shared auth flows
│   └── zopiq_maps/            # maps wrapper
├── infra/
│   ├── terraform/
│   ├── helm/
│   ├── k8s/
│   └── argocd/
├── contracts/                 # OpenAPI + protobuf definitions
├── docs/
├── scripts/
└── .github/workflows/
```

## 6.2 Flutter App Internal (feature-first Clean Architecture)
```
mobile_customer/
├── lib/
│   ├── main.dart / main_dev.dart / main_prod.dart   # flavors
│   ├── app/                    # MaterialApp, router, DI setup
│   ├── core/                   # errors, network, constants, utils, extensions
│   ├── config/                 # env, flavors, theme config
│   ├── l10n/                   # localization arb files
│   ├── shared/                 # shared widgets, mixins
│   └── features/
│       ├── auth/
│       │   ├── data/           # datasources, repositories_impl, models
│       │   ├── domain/         # entities, repositories, usecases
│       │   └── presentation/   # pages, widgets, bloc/riverpod
│       ├── home/
│       ├── search/
│       ├── restaurant/
│       ├── grocery/
│       ├── product/
│       ├── cart/
│       ├── checkout/
│       ├── payment/
│       ├── orders/
│       ├── tracking/
│       ├── wallet/
│       ├── profile/
│       ├── support/
│       └── notifications/
├── test/
├── integration_test/
└── pubspec.yaml
```

## 6.3 Backend Service Internal (NestJS)
```
order-service/
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   ├── modules/
│   │   └── orders/
│   │       ├── orders.controller.ts
│   │       ├── orders.service.ts
│   │       ├── orders.repository.ts
│   │       ├── dto/
│   │       ├── entities/
│   │       ├── events/
│   │       └── orders.module.ts
│   ├── common/            # guards, interceptors, filters, pipes
│   ├── config/
│   ├── database/          # migrations, seeds
│   ├── events/            # Kafka producers/consumers
│   └── health/
├── test/
├── Dockerfile
└── package.json
```

## 6.4 React Admin Internal (feature modules)
```
web_admin/src/
├── app/            # router, providers, layout
├── features/       # orders/, vendors/, riders/, finance/, marketing/, cms/, support/, ops/, analytics/
├── shared/         # api client, hooks, ui, rbac guards
├── config/
└── locales/
```

---
---

# SECTION 7 — FLUTTER ARCHITECTURE

## 7.1 Chosen Architecture: **Feature-first Clean Architecture**
Three layers per feature: **Presentation → Domain → Data**. Dependencies point inward (Domain has zero framework deps).

**Why:** scalability across many features and 4 apps; testable domain; swappable data sources; parallel team work per feature; enforced boundaries prevent spaghetti at scale.

## 7.2 State Management: **Riverpod 2.x (primary)** + Bloc for complex flows
- **Riverpod** for most state (compile-safe DI + state), great testability.
- **Bloc/Cubit** optionally for complex multi-state flows (checkout, tracking) where explicit state machines help.
- **Decision:** Standardize on Riverpod app-wide; document exception process. `[DECISION-OWNER: Lead Flutter Eng]`

## 7.3 Dependency Injection
Riverpod providers + `get_it` for lower-level singletons (network client, storage). Providers wire repositories → usecases → notifiers.

## 7.4 Repository Pattern
Domain defines `abstract Repository`. Data layer implements with remote (Dio) + local (Hive/Isar/Drift) datasources. Repository decides cache vs network (cache-then-network).

## 7.5 Networking
- **Dio** + interceptors (auth token, refresh, retry, logging, error mapping).
- Generated clients from OpenAPI where possible.
- Typed `Result<T, Failure>` (fpdart `Either`) — no throwing across layers.

## 7.6 Offline Support & Caching
- **Isar/Drift** for structured local cache (catalog, orders, cart).
- Cart persisted locally + synced.
- Optimistic UI for cart ops.
- Offline banner; queued actions replay on reconnect.
- Image caching via `cached_network_image`.

## 7.7 Error Handling
- Central `Failure` hierarchy (Network, Server, Cache, Validation, Auth).
- Global error boundary + `runZonedGuarded` → Crashlytics/Sentry.
- User-facing error mapping (friendly messages) in presentation.

## 7.8 Localization
- `flutter_localizations` + `intl` + `.arb` files; keys, not hardcoded strings.
- RTL support. Number/currency/date locale formatting. Remote string overrides possible.

## 7.9 Theme & Design System (`zopiq_ui`)
- Material 3, light/dark, dynamic color tokens.
- Design tokens (spacing, radius, typography, color) from Figma → Dart.
- Component library: buttons, inputs, cards (vendor/product), rating, bottom sheets, skeleton loaders, empty/error states.
- Single source of truth shared across all 4 Flutter apps.

## 7.10 Navigation
`go_router` — declarative, deep-link ready (order tracking links, referrals), guarded routes (auth).

## 7.11 Cross-cutting
- **Flavors:** dev/staging/prod with separate configs & Firebase projects.
- **Analytics wrapper** (single facade → Mixpanel/Firebase).
- **Feature flags** via Remote Config.
- **Performance:** const widgets, `ListView.builder`, image sizing, isolate for heavy parsing.
- **Security:** secure storage for tokens (`flutter_secure_storage`), certificate pinning, no secrets in code, obfuscation (`--obfuscate`).

---
---

# SECTION 8 — BACKEND ARCHITECTURE

## 8.1 Approach: **Modular Monolith → Microservices (evolutionary)**
- **MVP/Phase 1:** Modular monolith (NestJS) with clear module boundaries + one Go service for dispatch/location. Faster to build, deploy, and debug with a small team.
- **Phase 3–4:** Extract high-load domains (order, payment, dispatch, location, search, notification) into independent services as scale demands.
- **Rationale:** Avoid premature microservice complexity; boundaries are drawn now (Section 6) so extraction is mechanical later.

## 8.2 API Gateway
Kong/Envoy: TLS termination, JWT validation, routing, rate limiting, request/response logging, CORS, API versioning (`/v1`). BFF layer (`admin-bff`, mobile GraphQL BFF optional) aggregates for clients.

## 8.3 REST vs GraphQL vs gRPC
- **Public/mobile:** REST (OpenAPI, versioned) — simple, cacheable. Optional GraphQL BFF for flexible mobile fetching.
- **Internal service-to-service:** gRPC (low latency, typed).
- **Events:** Kafka (async, decoupled).

## 8.4 Event-Driven Backbone (Kafka)
Domain events: `OrderCreated`, `OrderAccepted`, `PaymentCaptured`, `RiderAssigned`, `OrderDelivered`, `InventoryChanged`. Consumers: notifications, analytics, settlement, search-index, fraud. Enables replay, decoupling, audit.

## 8.5 Background Jobs / Workflows
- **BullMQ** (Redis) for jobs: send notification, index item, image processing.
- **Temporal** for long-running sagas: order lifecycle, refunds, settlements (durable, retryable, observable).
- **Cron/scheduled:** settlement runs, subscription renewals, stale-cart cleanup, report generation.

## 8.6 Scalability & Horizontal Scaling
- Stateless services behind LB; scale via HPA (K8s) on CPU/RPS/queue-depth.
- DB: read replicas, connection pooling (PgBouncer), partitioning, later sharding by region/user.
- Redis cluster; Kafka partitions by key (order_id/user_id).
- CDN for static + image; edge caching for catalog.
- Idempotency keys on order/payment endpoints.
- Circuit breakers + bulkheads (resilience4j-style) for downstream (maps, gateway).

## 8.7 Caching Strategy
- **L1:** in-process (short TTL config).
- **L2:** Redis — hot catalog, vendor lists by geohash, serviceability, sessions, rate-limit counters, cart, rider geo.
- Cache invalidation via events (catalog change → bust keys).

## 8.8 Rate Limiting
Per-IP + per-user + per-endpoint (token bucket in Redis) at gateway; stricter on auth/OTP/payment.

## 8.9 Observability
- **Metrics:** Prometheus (RED/USE), Grafana dashboards, SLO alerts.
- **Tracing:** OpenTelemetry → Jaeger; trace IDs propagated to clients.
- **Logging:** structured JSON, correlation IDs, centralized (Loki/ELK).
- **Health:** liveness/readiness probes; synthetic checks; status page.

## 8.10 Data Consistency
- Transactional integrity within service DB.
- Cross-service: Saga pattern (Temporal) with compensating actions (e.g., payment captured but store rejects → refund saga).
- Outbox pattern for reliable event publish.

---
---

# SECTION 9 — AUTHENTICATION & AUTHORIZATION

## 9.1 Methods by Persona
| Persona | Primary | Secondary | MFA |
|---|---|---|---|
| Customer | Phone OTP | Google, Apple, Email | Optional |
| Restaurant staff | Email/password | Phone OTP | Recommended |
| Grocery staff | Email/password | Phone OTP | Recommended |
| Delivery partner | Phone OTP | — | Device binding |
| Admin | Email/password | SSO (Google Workspace) | **Mandatory (TOTP)** |
| Super Admin | SSO + hardware key | — | **Mandatory + IP allowlist** |
| Support | Email/password + SSO | — | Mandatory |

## 9.2 Token Strategy
- **Access token:** JWT, short-lived (15 min), signed (RS256), contains user_id, roles, scopes.
- **Refresh token:** opaque, rotating, stored hashed server-side (`auth_sessions`), long-lived (30 days), revocable per device.
- Rotation on each refresh; reuse detection → revoke session family.
- Token stored in secure storage (mobile) / httpOnly cookie (web admin).

## 9.3 OTP
6-digit, hashed, 5-min TTL, max 5 attempts, resend cooldown, rate-limited per phone/IP. Multi-provider SMS failover. Silent OTP autofill (Android SMS Retriever). WhatsApp OTP fallback.

## 9.4 Social Login
Google Sign-In, Apple Sign-In (required for iOS). Link to existing phone account by verified email/phone.

## 9.5 RBAC & Permissions
- Roles: `customer`, `vendor_owner`, `vendor_staff`, `rider`, `support_agent`, `support_lead`, `ops`, `finance`, `marketing`, `admin`, `super_admin`.
- Permissions granular (e.g., `order.refund`, `vendor.approve`, `coupon.create`, `pii.view`).
- Scoped roles: vendor staff scoped to `vendor_id`; ops scoped to `region_id`.
- Enforced at gateway (coarse) + service (fine) via guards.
- Every privileged action → `audit_logs`.
- **Impersonation:** super-admin/support can impersonate with explicit audit trail + banner.

## 9.6 Session & Security
- Device management (list/revoke devices).
- Forced logout on password change / suspicious activity.
- Account lockout on brute force.
- Force-update gate via `app_versions`.

---
---

# SECTION 10 — DELIVERY LOGIC

## 10.1 Vendor Assignment
- Order routed to vendor(s) by cart. Multi-vendor → split into `order_vendors` sub-orders, each accepted independently, coordinated for single delivery when feasible (same-zone batching).

## 10.2 Nearest / Best Driver (Dispatch Service — Go)
Algorithm (not naive nearest):
1. Candidate riders: online, in zone, within radius, capacity available.
2. Score = f(distance to pickup, current load, direction of travel, rider rating, acceptance rate, fairness/rotation, ETA to pickup).
3. Offer to top rider(s); timeout → next; escalate radius; fallback to 3P logistics.
4. **Batching:** if two orders share pickup zone + drop corridor + time window, combine into multi-drop task (route-optimized).

## 10.3 Route Optimization
Google Directions + internal solver for multi-stop sequencing (TSP heuristic for ≤ N stops). ETA from Distance Matrix + historical traffic + prep-time.

## 10.4 Order Splitting & Batching
- **Split:** multi-vendor cart → parallel prep, joined at delivery when geographically sensible; else separate deliveries with combined tracking view.
- **Batch:** grocery q-commerce orders from same dark store batched by picking + route.

## 10.5 Live Tracking
Rider app streams location (MQTT/WS, throttled 3–5s) → location-service → Redis Geo + fan-out to customer via WS. Customer sees rider marker, ETA, status timeline. Store/kitchen status also surfaced (tri-tracking USP).

## 10.6 Delivery Radius & Serviceability
Per-vendor radius + service zones (polygons). Real-time serviceability check at home/checkout. Grocery limited to dark-store catchment (≤ ~3km for 10-min promise).

## 10.7 Delivery Charge Engine
| Component | Rule |
|---|---|
| Base fee | Flat per vertical |
| Distance fee | Per-km beyond base distance |
| Surge multiplier | Demand/supply ratio, time-based |
| Weather (rain) fee | Weather API trigger |
| Night charge | Time-window (e.g., 11pm–6am) |
| Small-cart fee | Below min order value |
| Peak/festival fee | Admin-configured events |
| zopiqPRO waiver | Subscription overrides fees |
| Long-distance/heavy | Weight-based (grocery) |

All fees itemized transparently at checkout (USP: zero-surprise pricing). Rules engine is admin-configurable per zone/time.

## 10.8 Proof of Delivery & Exceptions
OTP-based handoff (default), photo/contactless option, signature for high-value. Exceptions: customer unavailable → retry/return workflow; wrong address; damaged item → support flow.

---
---

# SECTION 11 — RESTAURANT FEATURES (Detailed)

| Area | Capabilities |
|---|---|
| Menu | Categories, items, variants (size/portion), addon groups (min/max, required/optional), item photos, veg/non-veg, spice level, allergens, availability schedule (breakfast/lunch), out-of-stock toggle |
| Orders | Real-time inbox, sound alert, accept/reject with reason, set/adjust prep time, mark ready, order history, reprint KOT |
| Availability | Open/close store, holiday mode, item-level 86'ing, busy-mode throttle |
| Pricing/Offers | Item discounts, combo meals, happy-hour pricing, flat/percent offers, free-item, BOGO |
| Analytics | Sales trends, top items, order funnel, avg prep time, rejection rate, ratings breakdown, customer repeat rate, peak hours heatmap |
| Finance | Daily/weekly earnings, commission breakdown, settlement schedule, payout status, downloadable invoices, tax (GST) reports, TDS |
| Reviews | View + respond, flag abusive |
| Ads | Promoted listing purchase, banner slots, sponsored search |
| Multi-outlet | Org-level view, per-branch menus, consolidated reports |
| Integrations | POS/aggregator sync (later), printer/KDS |
| Support | Vendor support chat, dispute raising, escalation |

**Payout & Settlement flow:** order delivered → commission + taxes computed → aggregated per settlement period → deductions (ads, penalties, refunds) → net → payout via bank → invoice + statement generated.

---
---

# SECTION 12 — GROCERY STORE / DARK-STORE FEATURES (Detailed)

| Area | Capabilities |
|---|---|
| Catalog | SKU with brand, barcode, unit/weight/pack, images, nutrition, HSN, MRP vs sell price |
| Inventory | Real-time stock, reserved qty, multi-batch, bin/location, reorder levels, cycle counting |
| Barcode/SKU | Scanner-based stock-in, picking scan verification |
| Expiry | Batch + expiry tracking, FEFO picking, near-expiry markdown, waste reporting |
| Variants | Weight/size variants, loose vs packed |
| Pricing | MRP, sell price, margin, dynamic markdown, bulk pricing |
| Offers | Combos, bundles, flash sales (time-boxed), BOGO, category discounts, coupon eligibility |
| Fulfillment | Pick list generation, packing station, quality check, handoff to rider, substitution suggestions on OOS |
| Supply chain | Purchase orders, supplier management, GRN, stock transfer between stores |
| Analytics | Fill rate, OOS rate, waste %, top SKUs, demand forecast, assortment gaps |
| Finance | Same settlement/payout/tax structure as restaurants |
| Substitutions | Auto-suggest replacement on OOS with customer approval flow |

**Q-commerce specifics:** dark-store assortment optimized per neighborhood demand (AI), sub-15-min picking SLA, real-time inventory decrement on order confirmation with reservation locks to prevent oversell.

---
---

# SECTION 13 — CUSTOMER FEATURES (Screen-by-Screen)

## 13.1 Screen Inventory & Workflows
| # | Screen | Key Elements | Workflow |
|---|---|---|---|
| 1 | Splash | Logo, version/force-update check, session restore | Check token → route home/onboarding |
| 2 | Onboarding | 3–4 value slides | Skip/next → login |
| 3 | Login | Phone input, social buttons | Enter phone → OTP |
| 4 | OTP | 6-box input, resend timer, autofill | Verify → profile/home |
| 5 | Profile Setup | Name, email (optional) | Save → location |
| 6 | Location Permission/Select | GPS, map pin, saved addresses, search | Set → serviceability check → home |
| 7 | Home | Vertical switcher (Food/Grocery), search bar, location, banners, categories, personalized rails ("Craving Engine"), reorder, offers | Browse → vendor/product |
| 8 | Vertical: Food Home | Cuisines, top restaurants, filters (veg, rating, price, offers) | |
| 9 | Vertical: Grocery Home | Categories grid, deals, "buy again", flash sale | |
| 10 | Search | Unified search, suggestions, recent, trending, voice search | Query → results (vendors+items) |
| 11 | Search Results | Tabs (restaurants/dishes/products), filters, sort | |
| 12 | Restaurant Detail | Header (name, rating, ETA, offers), menu (categories, items), veg toggle, search-in-menu, info tab | Add item → cart |
| 13 | Grocery Store/Category | SKU grid, filters, subcategories | |
| 14 | Item/Food Detail | Images, price, variants, addons, description, allergens, add-to-cart with qty | Configure → add |
| 15 | Cart | Items (grouped by vendor), qty edit, addons, coupon field, bill summary (itemized), tip, add-more | Proceed → checkout |
| 16 | Checkout | Address select, delivery slot (now/scheduled), payment method, coupon, instructions, contactless toggle, final bill | Place order |
| 17 | Payment | UPI/cards/wallet/netbanking/COD, saved methods, gateway flow | Pay → confirmation |
| 18 | Order Confirmation | Success animation, order no, ETA, track button | → tracking |
| 19 | Live Tracking | Map (rider+vendor markers), status timeline, ETA, rider contact/chat, tri-tracking, help | Real-time updates |
| 20 | Orders List | Active + past, reorder, invoice, rate | |
| 21 | Order Detail | Items, bill, status history, invoice download, support, cancel/return | |
| 22 | Profile | Info edit, addresses, payment methods, zopiqPRO, referrals, settings | |
| 23 | Wallet | Balance, add money, transaction history, refunds | |
| 24 | Addresses | List, add/edit (map), set default | |
| 25 | Payment Methods | Saved cards/UPI, add/remove | |
| 26 | Coupons/Offers | Available offers, apply, code entry | |
| 27 | Favorites | Saved vendors/items | |
| 28 | zopiqPRO | Plan details, subscribe, benefits, manage | |
| 29 | Referrals | Code, share, status, rewards | |
| 30 | Notifications | List, deep-links | |
| 31 | Reviews | Rate order/item/rider, photos | |
| 32 | Support/Help | Ticket list, chat, bot, FAQ, order-specific help | |
| 33 | Settings | Language, notifications prefs, theme, privacy, delete account, logout | |
| 34 | Group Order | Create/join shared cart | |
| 35 | Gift Order | Recipient details, message | |
| 36 | Scheduled Orders | Slot picker, manage | |
| 37 | Empty/Error/Offline states | Illustrations, retry | |
| 38 | Serviceability-unavailable | "Coming soon", notify-me | |

Every button maps to a use case → repository → API. Skeleton loaders on all lists; optimistic cart updates; pull-to-refresh; pagination on all feeds.

---
---

# SECTION 14 — DELIVERY PARTNER FEATURES (Detailed)

| Area | Capabilities / Screens |
|---|---|
| Onboarding/KYC | Phone OTP, personal details, document upload (ID, license, RC, insurance, PAN), vehicle info, bank account, selfie, verification status tracking |
| Duty | Online/offline toggle, zone selection, shift start/end |
| Order flow | Offer screen (pickup/drop, distance, earning, timer), accept/reject, pickup navigation, arrived-at-store, verify items, picked-up, drop navigation, arrived, POD (OTP/photo), delivered |
| Navigation | Turn-by-turn (Google/embedded), reroute, multi-stop sequence for batches |
| Batching | Ordered stop list, per-stop actions |
| Earnings | Today/week/month, per-order breakdown (base+distance+surge+incentive+tip), incentive progress bars, payout history |
| Incentives | Streaks, peak bonuses, referral, milestone; heat-map of high-demand zones |
| Wallet | Balance, instant withdrawal, statements |
| COD | Amount to collect, running cash-in-hand, deposit reconciliation, limits |
| Ratings | Score, tier (bronze/silver/gold), feedback, improvement tips |
| Safety | SOS button, share live trip, emergency contacts, insurance info |
| Support | Chat, order dispute, help |
| Profile | Docs, vehicle, bank, availability preferences |
| Notifications | New order, incentive, payout, announcements |

**Constraints:** cash-in-hand limit blocks new COD when exceeded; forced document re-verification on expiry; performance-based suspension workflow.

---
---

# SECTION 15 — ADMIN FEATURES (Detailed)

| Module | Capabilities |
|---|---|
| Dashboard | Live KPIs: orders, GMV, active riders, active vendors, SLA breaches, revenue, alerts |
| Order Management | Global search/filter, order 360°, manual reassign rider, force-cancel, override status, dispute resolution, bulk actions |
| Vendor Management | Onboarding queue, KYC review/approve/reject, edit vendor, commission override, suspend, performance, catalog moderation |
| Rider Management | KYC review, activate/suspend, zone assignment, performance, incident handling |
| Catalog Moderation | Approve items/images, flag policy violations, bulk edit, taxonomy management |
| Pricing/Commission | Commission tiers, delivery-fee rules, surge config, tax rules per zone |
| Promotions | Coupon CRUD, campaigns, banners, offers, budget tracking, targeting (segment/geo) |
| Payments/Finance | Transactions, refunds approval, settlements, payout runs, ledger, reconciliation, disputes/chargebacks |
| CMS | Banners, home rails config, static pages, app config, remote strings |
| Marketing | Push/SMS/email/WhatsApp campaigns, segmentation, A/B tests, scheduling, performance |
| Users | Search, 360° view, block/unblock, fraud flags, wallet adjust (audited), impersonate |
| Geo/Zones | Draw service zones, serviceability toggle, dark-store catchment |
| Reports/Analytics | GMV, cohort/retention, funnel, vendor/rider performance, financial, custom exports |
| Feature Flags | Toggle features, gradual rollout, kill-switches |
| Audit | View all privileged actions, filter by actor/entity |
| Support Config | SLA rules, canned responses, KB management |
| System Health | Service status, queue depth, error rates (link to Grafana) |

---
---

# SECTION 16 — SUPPORT DASHBOARD (Detailed)

| Feature | Description |
|---|---|
| Ticket Queue | Unified queue (customer/vendor/rider), priority, SLA timers, filters, assignment/auto-routing |
| Order 360° Context | Full order timeline, payments, rider path, chat history, refunds — one screen |
| Live Chat | Multi-conversation, typing indicators, attachments, canned responses, sentiment tags |
| Voice/Call | Click-to-call (CTI integration), call recording/logs, IVR handoff |
| Refunds/Compensation | Bounded issuance (agent limits), approval chain above threshold, wallet credit/coupon issue |
| Escalation | Tiered escalation, reassignment, internal notes, escalate to ops/finance |
| Bot Handoff | AI first-line (LLM) resolves FAQ/status; escalates with context to human |
| Knowledge Base | Searchable articles, macros, decision trees |
| CSAT | Post-resolution survey, agent scorecards |
| SLA & Reporting | First-response/resolution times, backlog, agent performance |
| Fraud/Abuse flags | Mark accounts, trigger review |

---
---

# SECTION 17 — PAYMENT SYSTEM (Detailed)

## 17.1 Methods
UPI (intent + collect + autopay), cards (tokenized), net-banking, wallets (Paytm etc.), zopiq wallet, COD, BNPL (later), partial payment (wallet + gateway), tips.

## 17.2 Order Payment Flow
1. Checkout creates order (status `created`, payment `pending`) with **idempotency key**.
2. Payment intent created at gateway (Razorpay).
3. Client completes payment; gateway webhook → `payment.captured`.
4. On capture → order `confirmed` → vendor notified. On failure → retry/alternate method; auto-release inventory reservation.
5. COD → order confirmed immediately; collection at delivery.

## 17.3 Refunds
Full/partial; auto (cancel before accept) or agent-initiated; to source or wallet (instant). Refund saga via Temporal; reconciled against gateway.

## 17.4 Split & Merchant Settlement
- Customer pays platform; platform is merchant of record.
- Per-order: split into vendor payable + platform commission + delivery + taxes + rider payout.
- Settlement engine aggregates per period → deductions → net → payout (bank transfer/UPI) → invoices.
- **Double-entry ledger** for every money movement; daily reconciliation vs gateway settlements.

## 17.5 Taxes & Invoices
GST (CGST/SGST/IGST) computed per HSN/SAC & vendor state; invoices for customer, vendor commission invoice, rider statement. TDS/TCS as per regulation. Downloadable PDFs.

## 17.6 Wallet
Prepaid balance, refunds, cashback, loyalty. Ledger-backed. KYC limits per regulation. No interest (not a bank).

## 17.7 Financial Controls
PCI-DSS scope minimized (tokenization, no PAN storage), reconciliation jobs, fraud checks on payment, chargeback handling, dispute workflow, audit on every adjustment.

---
---

# SECTION 18 — NOTIFICATION SYSTEM

| Channel | Use | Provider |
|---|---|---|
| Push | Order status, offers, rider updates | FCM |
| SMS | OTP, critical order updates, fallback | MSG91/Twilio (failover) |
| Email | Invoices, receipts, marketing, statements | SES/SendGrid |
| WhatsApp | Order updates, OTP, re-engagement | WhatsApp Business API |
| In-app | Notification center, banners | Internal |

**Architecture:** notification-service consumes Kafka events → template engine → user preferences check → channel router → provider (with failover) → delivery tracking (`notifications`). Quiet hours, frequency caps, unsubscribe, DND compliance. Templates versioned & localized. Priority tiers (transactional bypasses caps). Deep-links in every push.

---
---

# SECTION 19 — MAPS

| Capability | API/Tech |
|---|---|
| Place search / autocomplete | Google Places |
| Address geocode / reverse | Google Geocoding |
| Distance & ETA | Distance Matrix + traffic |
| Routing / navigation | Directions API + rider nav |
| Live rider tracking | Rider location stream → Redis Geo → WS to customer |
| Serviceability | PostGIS polygons + point-in-polygon |
| Nearest driver | Redis Geo radius + dispatch scoring |
| Map rendering | Google Maps SDK (Flutter), Mapbox fallback for cost |

**Cost controls:** cache geocodes, debounce autocomplete (session tokens), batch distance matrix, use cheaper providers for non-critical rendering, self-host tiles later at scale.

---
---

# SECTION 20 — AI FEATURES

| Feature | Approach |
|---|---|
| Smart/semantic search | Elasticsearch + embeddings (pgvector) + LLM query understanding (typo, intent, NL "something spicy under 200") |
| Recommendations ("Craving Engine") | Feature store + ranking model; context: time, weather, history, location; food+grocery cross-sell |
| Chatbot / auto-support | Claude (LLM) with order context tools; resolves status/refund/FAQ, escalates with summary |
| Voice ordering | Speech-to-text → LLM intent → cart actions |
| Demand prediction | Time-series ML for dark-store stocking, rider positioning, prep-time estimation |
| Fraud detection | Rules + ML scoring: fake orders, promo abuse, refund abuse, rider collusion, device fingerprint, velocity checks |
| Dynamic pricing | Surge/delivery-fee ML on supply-demand, weather, time |
| Personalized offers | Segment + propensity models; next-best-offer |
| Review summarization | LLM summarizes vendor reviews into pros/cons |
| Image moderation/enrichment | Auto-tag food images, detect policy violations |
| Substitution intelligence | Best replacement suggestion on grocery OOS |
| ETA prediction | ML on historical + live traffic + prep + batching |

**Governance:** human-in-loop for money actions, guardrails/PII redaction on LLM prompts, model monitoring, A/B evaluation, fallback to deterministic rules.

---
---

# SECTION 21 — SECURITY

| Domain | Controls |
|---|---|
| OWASP Top 10 | Input validation, output encoding, parameterized queries (no SQLi), authZ checks, SSRF/RCE prevention, dependency scanning |
| Encryption | TLS 1.3 in transit; AES-256 at rest (DB, S3); field-level encryption for PII (phone/email/bank); KMS-managed keys |
| Secrets | Vault/Secrets Manager; no secrets in code/repo; rotation; scoped IAM |
| API security | JWT validation, scope checks, rate limiting, idempotency, request signing (webhooks), API keys for partners, replay protection |
| Injection/XSS/CSRF | Prepared statements, ORM, CSP headers, sanitization, CSRF tokens (web), SameSite cookies |
| Mobile | Cert pinning, root/jailbreak detection, code obfuscation, secure storage, no PII in logs, tamper detection |
| AuthZ | RBAC + scoped permissions, least privilege, deny-by-default |
| Audit | Immutable audit logs for privileged/financial actions, tamper-evident |
| Rate limiting/DoS | Gateway limits, WAF (Cloudflare/AWS WAF), bot detection, CAPTCHA on sensitive flows |
| Data privacy | GDPR/India DPDP: consent, data export, right-to-delete, PII minimization, retention policies, access controls, DPO |
| Payments | PCI-DSS scope reduction (tokenization), no card storage, gateway-hosted fields |
| Fraud | Device fingerprint, velocity, promo-abuse detection, KYC, blacklists |
| Infra | Private subnets, security groups, least-privilege IAM, image scanning, secrets scanning in CI, SBOM, patch management |
| SDLC | SAST/DAST, dependency audit (Snyk/Dependabot), pen-test before launch, bug bounty (later), secure code review |
| Incident response | Runbooks, on-call, kill-switch, breach notification process |

---
---

# SECTION 22 — PERFORMANCE

| Layer | Techniques |
|---|---|
| App startup | Deferred init, splash prefetch, minimal main-thread work, tree-shaking, `--obfuscate --split-debug-info` |
| Lists/feeds | Lazy loading, `ListView.builder`, pagination (cursor), skeleton loaders, image placeholders |
| Images | CDN + on-the-fly resize (WebP/AVIF), responsive sizes, cached_network_image, blurhash |
| Caching | Client (Isar) + Redis + CDN edge; cache-then-network; stale-while-revalidate |
| API | Response compression (gzip/brotli), field selection, batching, avoid N+1 (dataloader/joins), read replicas, pagination everywhere |
| DB | Indexes, query plans, partitioning, connection pooling, materialized views for analytics |
| Realtime | Throttled location updates, delta payloads, WS instead of polling |
| Backend | Horizontal scaling, caching hot paths, async/event-driven, circuit breakers |
| Monitoring | p50/p95/p99 latency SLOs, Apdex, Core Web Vitals (web), Flutter frame timing |
| Payloads | Slim DTOs, avoid over-fetch, protobuf internal |
| Cold-start | Provisioned capacity for critical services |

**Targets:** app cold start < 2.5s; home feed < 1s (cached); p95 API < 300ms; search < 200ms; tracking update ≤ 5s; 60fps scroll.

---
---

# SECTION 23 — TESTING STRATEGY

| Type | Scope | Tools |
|---|---|---|
| Unit (mobile) | Domain/usecases, repos, utils | flutter_test, mocktail |
| Widget | Components, screens | flutter_test, golden_toolkit |
| Integration (mobile) | Flows (login→order) | integration_test, Patrol |
| Unit (backend) | Services, business logic | Jest |
| API/contract | Endpoints, OpenAPI conformance | Supertest, Pact (contract) |
| E2E | Full user journeys | Detox/Maestro (mobile), Playwright (web) |
| Load | Throughput, order surge | k6, Locust |
| Stress/soak | Breaking points, memory leaks | k6, Gatling |
| Chaos | Resilience (kill pods, latency) | Chaos Mesh |
| Security | SAST/DAST, pen-test | Snyk, OWASP ZAP, Burp |
| Performance | Latency, frame budget | Grafana, Flutter DevTools |
| Accessibility | Screen-reader, contrast | axe, Flutter a11y |
| Regression | Golden tests, snapshot | golden_toolkit |
| Data | Migration integrity, reconciliation | custom |

**Coverage gates:** domain ≥ 80%, critical paths (payment/order) ≥ 90%. CI blocks on failing tests + coverage drop. Staging soak before prod. Synthetic monitoring in prod.

---
---

# SECTION 24 — DEPLOYMENT

## 24.1 Environments
| Env | Purpose | Data |
|---|---|---|
| Local | Dev | Seed/mock |
| Dev | Shared integration | Synthetic |
| Staging | Pre-prod, QA, load | Prod-like (masked) |
| Production | Live | Real |

## 24.2 CI/CD
- **CI (GitHub Actions):** lint → test → build → security scan → container build → push registry → generate SBOM.
- **CD (ArgoCD/GitOps):** Helm charts, promote via PR; canary/blue-green; automatic rollback on health/SLO breach.
- **Mobile:** Fastlane → Play Console (internal → closed → open → prod tracks); staged rollout %; Firebase App Distribution for QA; code-push not used (native), so force-update gating instead.
- **DB migrations:** versioned, backward-compatible (expand/contract), run pre-deploy, reversible.

## 24.3 Containerization & Orchestration
Docker images (distroless), Kubernetes (EKS), Helm, HPA, PodDisruptionBudgets, network policies, secrets via Vault CSI.

## 24.4 Monitoring & Rollback
Prometheus/Grafana alerts → PagerDuty/Opsgenie on-call. Canary metrics gate promotion. One-click rollback (ArgoCD). Feature flags for instant disable without redeploy. Runbooks per service.

## 24.5 Release Cadence
Trunk-based dev, short-lived branches, feature flags, weekly releases (backend), bi-weekly (mobile), hotfix path.

---
---

# SECTION 25 — ROADMAP

| Phase | Name | Duration | Difficulty | Key Scope | Dependencies |
|---|---|---|---|---|---|
| **P1** | MVP (single city, food + one dark store) | ~14–18 wks | High | Auth, catalog, cart, checkout, payments (UPI/COD), single-vendor orders, basic dispatch, live tracking, customer+vendor+rider apps (core), basic admin, notifications | Infra, design system, payment gateway |
| **P2** | Beta (multi-vendor, grocery scale) | ~10–12 wks | High | Multi-vendor cart, grocery inventory depth, batching, wallet, coupons, ratings, support dashboard, analytics, marketing tools, subscriptions | P1, dispatch maturity |
| **P3** | Launch (city expansion, hardening) | ~10–12 wks | Med-High | Surge/dynamic pricing, AI reco + search, fraud detection, settlements/finance dashboard, WhatsApp, referrals, performance/scale, security audit, iOS | P2, ML infra |
| **P4** | Scale (multi-city, super-app) | Ongoing | Very High | Microservice extraction, multi-region, group/gift/scheduled orders, pharmacy/pet, ads platform, advanced AI, fintech, EV fleet | P3, org scaling |

---
---

# SECTION 26 — PROJECT TIMELINE (Weekly Milestones, MVP-focused)

> Assumes parallel squads: Platform/Infra, Backend, Mobile-Customer, Mobile-Vendor/Rider, Web-Admin, QA, Design. Weeks indicative.

| Week | Milestone |
|---|---|
| W1 | Repo/monorepo setup, CI/CD skeleton, infra (K8s, DB, Redis, Kafka) via Terraform, design system kickoff, OpenAPI contracts drafted |
| W2 | Auth service + OTP + JWT/refresh; Flutter app shells (4) with flavors, DI, theme; admin shell + RBAC |
| W3 | User/profile/address services; location & serviceability; maps integration; customer onboarding+home shell |
| W4 | Catalog service (food+grocery), categories/items/variants/addons; vendor onboarding + menu mgmt (vendor app) |
| W5 | Inventory service (grocery), search service indexing; customer browse (restaurant/store/detail) |
| W6 | Cart service + pricing engine; customer cart UI; coupons basic |
| W7 | Order service + lifecycle state machine; checkout UI; vendor order inbox |
| W8 | Payment service + Razorpay (UPI/cards) + COD; wallet ledger basics; refunds path |
| W9 | Dispatch service (nearest driver), rider app order flow, POD; delivery-fee engine |
| W10 | Live tracking (location stream + WS), tri-tracking UI; notification service (push/SMS) |
| W11 | Admin: order/vendor/rider management, verification portal; settlement basics |
| W12 | Reviews/ratings; order history/reorder; support ticket MVP |
| W13 | Analytics ingestion, basic dashboards; finance reconciliation; hardening |
| W14 | End-to-end QA, load test, security pass, bug-bash; staging soak |
| W15 | Beta rollout (closed), monitoring, fixes |
| W16 | MVP launch (single city), on-call, iterate |

(P2/P3 milestones expand per Section 25.)

---
---

# SECTION 27 — RISKS

| Category | Risk | Impact | Mitigation |
|---|---|---|---|
| Technical | Dispatch/location scale under surge | High | Go services, Redis Geo, load-test early, autoscale, batching |
| Technical | Payment/order consistency | High | Idempotency, sagas, double-entry ledger, reconciliation |
| Technical | Inventory oversell (q-commerce) | High | Reservation locks, real-time decrement, single source of truth |
| Technical | Realtime tracking reliability | Med | WS/MQTT, fallbacks, throttling, degradation to polling |
| Technical | Microservice premature complexity | Med | Modular monolith first |
| Business | Two-sided liquidity (no vendors/riders) | High | Phased city launch, incentives, seeding |
| Business | Unit economics negative | High | Delivery-fee engine, batching, subscription, dark-store margin |
| Business | Vendor/rider churn | Med | Fair dispatch, timely payouts, support |
| Security | Data breach / PII leak | Very High | Encryption, least privilege, audits, pen-test, DPDP compliance |
| Security | Promo/refund/fraud abuse | High | Fraud ML, limits, KYC, velocity checks, audit |
| Scaling | DB bottleneck | High | Read replicas, partitioning, caching, sharding roadmap |
| Scaling | Cost of maps/SMS/cloud | Med | Caching, provider failover, negotiate rates, cost dashboards |
| Legal | FSSAI/GST/labor/gig-worker regs | High | Legal counsel, compliance module, licenses, insurance |
| Legal | Data localization (India) | High | India-region hosting, DPDP compliance |
| Ops | Delivery SLA misses / bad CSAT | Med | Realistic ETAs, capacity planning, support tooling |
| People | Key-person / hiring | Med | Docs (this SAD), pairing, knowledge sharing |

---
---

# SECTION 28 — FUTURE FEATURES

Drone delivery (regulated corridors), EV fleet + charging network, milk/newspaper subscriptions, cloud kitchens (owned brands), expanded dark stores, medicine/pharmacy (Rx upload + licensing), pet food & supplies, pickup/takeaway orders, group orders, corporate/B2B accounts & invoicing, gift orders, scheduled delivery, international expansion (multi-currency/language/tax), zopiq Mall (long-tail retail), fintech (BNPL, vendor loans, insurance), live vendor video/reels, AR menu, sustainability (carbon-neutral delivery, reusable packaging), in-app games/gamified loyalty, voice-assistant integrations (Alexa/Google), offline kiosks, franchise/white-label platform.

---
---

# SECTION 29 — MISSING FEATURES (Google Senior Architect Review)

> A critical pass to catch what the above might miss. Everything here is **now included** in scope.

## 29.1 Missing Features / Capabilities
- **Cancellation & refund policy engine** (time-based free cancel windows, fees).
- **Substitution & out-of-stock mid-order handling** (grocery) with customer approval.
- **Partial delivery / partial refund** (some items unavailable).
- **Return & replacement flow** (damaged/wrong grocery items).
- **Contactless delivery + delivery instructions + photo POD.**
- **Tipping** (pre/post delivery) and rider gratitude.
- **No-contact "leave at door"; call-on-arrival options.**
- **Multiple simultaneous carts** (food + grocery held separately) & cart merge rules.
- **Dietary profiles, allergen warnings, calorie/nutrition display.**
- **Age verification** (alcohol/restricted — future).
- **Reorder & "buy again" + subscription reorders.**
- **Waitlist / notify-me for OOS or unserviceable areas.**
- **Vendor holiday/vacation mode + auto-close on overload.**
- **Rider batching UI + earnings transparency + surge visibility.**
- **Referral & loyalty tiers; gamification.**
- **Multi-address & multi-recipient (gift) support.**
- **Guest checkout (web) & account merge.**
- **In-app rider ↔ customer masked calling/chat (privacy).**
- **Masked phone numbers (proxy) for all parties.**
- **Ratings for packaging, delivery, food separately.**
- **Complaint categories + evidence upload.**
- **Scheduled & recurring orders.**
- **Corporate wallet / expense integration (future).**
- **Accessibility (WCAG) & low-bandwidth mode.**
- **App localization + regional content.**
- **Consent management + marketing preferences center.**

## 29.2 Missing Database Tables (added)
- `cancellation_policies`, `return_requests`, `substitutions`, `partial_fulfillments`.
- `masked_call_sessions`, `proxy_numbers`.
- `tips`, `tip_payouts`.
- `waitlist_requests`, `serviceability_requests`.
- `vendor_penalties`, `rider_penalties`, `incident_reports`.
- `sla_configs`, `sla_breaches`.
- `feature_flags`, `remote_configs`, `app_versions` (force-update).
- `consents`, `data_deletion_requests`, `data_export_requests` (DPDP/GDPR).
- `device_fingerprints`, `fraud_scores`, `blacklists`.
- `dispatch_metrics`, `zone_demand_forecasts`.
- `webhooks`, `webhook_deliveries` (vendor integrations).
- `notification_preferences`, `dnd_windows`.
- `ledger_accounts`, `reconciliation_runs`, `chargebacks`.
- `search_synonyms`, `search_boosts`.
- `experiments`, `experiment_assignments` (A/B).
- `announcements`, `banners_schedule`.
- `packaging_options`, `packaging_fees`.
- `slots`, `slot_capacities` (scheduled delivery).
- `store_transfers`, `grn`, `suppliers`, `purchase_orders`.
- `rider_cash_limits`, `cod_deposits`.
- `loyalty_tiers`, `tier_benefits`.

## 29.3 Missing APIs (categories added)
- Serviceability check, slot availability, ETA estimate.
- Cart validation & repricing on checkout (prevent stale-price abuse).
- Idempotent order placement + payment intent.
- Webhook receivers (gateway, SMS, WhatsApp) + signature verification.
- Vendor availability/throttle, item 86-ing, bulk catalog import (CSV).
- Rider assignment/accept/reject/location-report/POD.
- Refund initiate/approve, settlement generate, payout trigger.
- Fraud-score query, blacklist check.
- Consent record, data-export/delete request.
- Feature-flag fetch, remote-config, app-version check.
- Masked-call session create.
- Search suggest/autocomplete, synonyms admin.
- Notification send/preferences, template CRUD.
- Analytics event ingest (batch).
- Impersonation start/stop (audited).

## 29.4 Missing Screens (added)
- Serviceability-unavailable / notify-me.
- OOS-substitution approval (customer).
- Partial-delivery / return-request.
- Tipping screen.
- Masked-call/chat screen.
- Slot picker (scheduled).
- Consent & privacy center; delete-account flow.
- Vendor: holiday mode, throttle, bulk import, penalty/dispute view.
- Rider: cash-limit warning, deposit reconciliation, SOS, safety.
- Admin: audit viewer, feature-flags, experiments, reconciliation, SLA dashboard, incident management, zone/surge editor.
- Support: order 360°, escalation, bot-handoff.
- Force-update / maintenance-mode screen.
- Error/empty/offline/skeleton states for every list.

## 29.5 Missing Workflows (added)
- Payment-failed → auto inventory release → retry.
- Vendor rejects after payment → auto refund saga + reassign/refund.
- Rider no-show/timeout → reassignment escalation.
- Multi-vendor coordination for single delivery.
- Dispute → investigation → resolution → compensation → ledger.
- Settlement → deductions → payout → invoice.
- KYC expiry → auto re-verification → suspension.
- Fraud score threshold → hold order → manual review.
- Data-deletion request → PII purge across services + retention exceptions.
- Chargeback → dispute → reconciliation.
- Surge activation/deactivation by demand-supply.

## 29.6 Missing Admin Features (added)
- Reconciliation & ledger explorer, chargeback management.
- Experiment/A-B management, feature-flag governance.
- SLA & incident management, on-call escalation view.
- Fraud review queue, blacklist management.
- Data-governance console (PII access, exports, deletions).
- Bulk operations (vendor onboarding, catalog import, coupon batch).
- Announcement/broadcast system.
- Cost/observability dashboards (maps/SMS/cloud spend).
- Vendor/rider penalty & incentive management.
- Multi-region config & kill-switch.

---
---

# SECTION 30 — EXECUTION DELIVERABLES

## 30.1 Development Dependency Graph
```
[Infra + CI/CD + Monorepo + Design System]
            │
            ▼
        [Auth Service] ──► [User/Profile] ──► [Address/Location/Serviceability]
            │                                        │
            ▼                                        ▼
     [RBAC/Admin Auth]                         [Maps Integration]
            │                                        │
            ▼                                        ▼
   [Vendor Service] ──► [Catalog Service] ──► [Inventory Service (grocery)]
            │                    │                   │
            │                    ▼                   │
            │             [Search Service] ◄─────────┘
            ▼                    │
   [Cart + Pricing] ◄───────────┘
            │
            ▼
     [Order Service (state machine)]
            │
      ┌─────┼───────────────┬───────────────┐
      ▼     ▼               ▼               ▼
[Payment] [Dispatch] [Notification] [Promo/Coupon]
   │        │               │               │
   ▼        ▼               │               │
[Wallet/  [Location/        │               │
 Ledger]  Tracking]         │               │
   │        │               │               │
   └────────┴───────┬───────┴───────────────┘
                    ▼
   [Reviews] [Support] [Settlement/Finance] [Analytics] [AI/Fraud/Reco]
                    │
                    ▼
              [Admin Modules] ──► [Marketing/CMS/Ops/Finance dashboards]
```
Rule: no node starts before its upstream contract (OpenAPI/proto) is frozen. Contracts-first enables parallel work.

## 30.2 API Implementation Order
1. Auth (OTP, login, refresh, social), device/session.
2. User/profile, addresses, consents.
3. Location/serviceability, zones, slots.
4. Vendor (onboarding, KYC, profile, hours).
5. Catalog (categories, items, variants, addons), search index.
6. Inventory (stock, reserve, decrement) — grocery.
7. Cart (add/update, validate, reprice), coupons apply.
8. Order (create idempotent, lifecycle, status, history).
9. Payment (intent, capture, webhook, COD), refunds.
10. Wallet/ledger, transactions.
11. Dispatch (assign, offer, accept/reject), rider location/POD.
12. Tracking (WS/stream, ETA).
13. Notifications (send, templates, preferences, webhooks).
14. Reviews/ratings.
15. Support (tickets, chat).
16. Settlement/payouts, invoices, taxes.
17. Promo/campaigns/banners/ads.
18. Analytics ingest, reporting.
19. Admin/RBAC, audit, feature-flags, experiments.
20. AI (search rank, reco, fraud, chatbot), masked calling.

## 30.3 Database Creation Order
1. `regions`, `cities`, `service_zones`.
2. `users`, `roles`, `permissions`, `role_permissions`, `user_roles`, `admin_users`, `auth_sessions`, `otp_requests`, `audit_logs`.
3. `addresses`, `consents`, `devices`.
4. `vendor_orgs`, `vendors`, `vendor_documents`, `vendor_bank_accounts`, `vendor_staff`, `vendor_working_hours`.
5. `categories`, `catalog_items`, `item_variants`, `addon_groups`, `item_addons`, `combos`, `item_price_history`.
6. `inventory`, `stock_history`, `suppliers`, `purchase_orders`, `po_line_items`, `grn`.
7. `carts`, `cart_items`.
8. `coupons`, `offers`, `campaigns`, `banners`, `ads`, `coupon_redemptions`.
9. `orders`, `order_vendors`, `order_items`, `order_status_history`, `delivery_tasks`, `slots`, `slot_capacities`.
10. `payments`, `refunds`, `saved_cards`, `cod_collections`, `chargebacks`.
11. `wallets`, `wallet_transactions`, `ledger_accounts`, `ledger_entries`.
12. `riders`, `rider_documents`, `rider_shifts`, `rider_earnings`, `rider_incentives`, `dispatch_offers`, `rider_cash_limits`, `cod_deposits`. (`rider_locations` → time-series store.)
13. `reviews`, `ratings_aggregate`.
14. `support_tickets`, `ticket_messages`, `chat_threads`, `chat_messages`, `canned_responses`, `kb_articles`.
15. `notifications`, `notification_templates`, `notification_preferences`.
16. `invoices`, `taxes`, `commissions`, `settlements`, `payouts`, `reconciliation_runs`.
17. `subscriptions`, `subscription_plans`, `loyalty_accounts`, `loyalty_transactions`, `loyalty_tiers`, `referrals`.
18. `feature_flags`, `remote_configs`, `app_versions`, `experiments`, `experiment_assignments`, `webhooks`, `webhook_deliveries`.
19. `fraud_scores`, `device_fingerprints`, `blacklists`, `incident_reports`, `sla_configs`, `sla_breaches`, `penalties`.
20. `data_deletion_requests`, `data_export_requests`, `search_synonyms`, `favorites`, `waitlist_requests`.

## 30.4 Flutter Screen Implementation Order
1. Splash, force-update, maintenance.
2. Onboarding, Login, OTP, Profile setup.
3. Location permission/select, serviceability-unavailable.
4. Home (vertical switcher) + shell/nav.
5. Search + results.
6. Restaurant detail / Grocery category + Item detail.
7. Cart.
8. Checkout (address, slot, coupon, bill).
9. Payment + confirmation.
10. Live tracking + tri-tracking.
11. Orders list + detail + reorder.
12. Wallet, addresses, payment methods.
13. Profile, settings, notifications center.
14. Reviews, favorites, coupons/offers.
15. Support/help/chat/bot.
16. zopiqPRO, referrals.
17. OOS-substitution, return/partial, tipping, masked-call.
18. Group/gift/scheduled orders.
19. Empty/error/offline/skeleton states throughout.
(Vendor & Rider apps: onboarding → order inbox/flow → earnings/analytics → support, in parallel.)

## 30.5 Backend Implementation Order
Follow 30.2 API order, grouped by service extraction readiness: build within modular monolith (auth→user→vendor→catalog→inventory→cart→order→payment→wallet→dispatch→tracking→notification→reviews→support→settlement→promo→analytics→admin→AI). Extract dispatch/location/search to standalone (Go/dedicated) early due to load profile.

## 30.6 Admin Panel Implementation Order
1. Auth + RBAC + layout/nav + audit.
2. Dashboard (KPIs).
3. Order management + 360°.
4. Vendor verification & management.
5. Rider verification & management.
6. Catalog moderation.
7. Coupons/promotions.
8. Payments/refunds.
9. Settlement/finance.
10. CMS (banners/config).
11. Marketing/campaigns.
12. Support dashboard.
13. Ops/dispatch control tower.
14. Analytics/reports.
15. Feature-flags/experiments.
16. Zone/surge/pricing config.
17. Fraud/incident/SLA.
18. Data governance / super-admin.

## 30.7 Testing Order
1. Unit (domain/services) alongside each module.
2. Contract tests (OpenAPI/Pact) as APIs land.
3. Widget tests per screen.
4. Integration tests per flow (auth→browse→cart→order→pay→track).
5. E2E critical journeys (customer, vendor, rider).
6. Security tests (SAST/DAST) in CI.
7. Load/stress on order/dispatch/payment before beta.
8. Chaos/resilience pre-launch.
9. Accessibility + localization pass.
10. UAT + bug-bash + staging soak.
11. Prod synthetic monitoring + canary validation.

## 30.8 Deployment Checklist
- [ ] Terraform infra applied (VPC, EKS, RDS, Redis, MSK, S3, CDN, WAF).
- [ ] Secrets in Vault; no secrets in repo.
- [ ] CI green: lint, tests, coverage gates, security scan, SBOM.
- [ ] DB migrations backward-compatible + reversible; run on staging first.
- [ ] Helm charts + ArgoCD apps configured; canary/blue-green set.
- [ ] Health/readiness probes; HPA; PDBs; network policies.
- [ ] Observability: metrics, tracing, logs, dashboards, alerts wired.
- [ ] Feature flags default-off for unfinished features.
- [ ] Rollback tested (one-click).
- [ ] Mobile: signed builds, staged rollout %, force-update config, Crashlytics.
- [ ] Payment gateway in live mode + webhooks verified.
- [ ] SMS/WhatsApp/email providers live + failover tested.
- [ ] Maps API keys, quotas, billing alerts.
- [ ] Backups + PITR verified; DR runbook.
- [ ] Status page + on-call rotation configured.

## 30.9 Production Readiness Checklist
- [ ] SLOs defined (uptime, p95 latency, error budget) + alerts.
- [ ] Load-tested to 3× expected peak; autoscaling verified.
- [ ] Data: backups, PITR, DR drill passed, RTO/RPO documented.
- [ ] Security: pen-test passed, OWASP addressed, secrets rotation, WAF, rate limits.
- [ ] PII: encryption, access controls, DPDP/GDPR (consent, export, delete).
- [ ] Financial: ledger reconciliation, idempotency, settlement dry-run, PCI scope minimized.
- [ ] Idempotency on order/payment; saga compensation tested.
- [ ] Observability: dashboards, tracing, log retention, runbooks per service.
- [ ] Incident response: on-call, escalation, kill-switch, comms plan.
- [ ] Capacity plan + cost dashboards.
- [ ] Legal: licenses (FSSAI/GST), vendor/rider contracts, terms/privacy, insurance.
- [ ] Accessibility + localization verified.
- [ ] Fraud detection live; abuse limits configured.
- [ ] Documentation: runbooks, API docs, onboarding, architecture (this doc) current.

## 30.10 Launch Checklist
- [ ] City/zone serviceability configured; dark-store stocked.
- [ ] Vendor supply seeded & verified; menus live & QA'd.
- [ ] Rider fleet onboarded, trained, KYC-verified, geared.
- [ ] Pricing, commissions, delivery fees, surge, taxes configured per zone.
- [ ] Launch coupons/offers configured + budget capped.
- [ ] App live on Play Store (staged rollout) + store listing/ASO.
- [ ] Marketing site + campaigns ready; support team trained + staffed.
- [ ] Support macros/KB/SLA configured; escalation paths tested.
- [ ] Payment/refund/settlement end-to-end verified with real money (small).
- [ ] Monitoring + war-room + on-call for launch window.
- [ ] Rollback/kill-switch ready; feature flags set.
- [ ] Legal/compliance sign-off.
- [ ] Post-launch: daily metrics review, rapid-fix loop, CSAT tracking, unit-economics dashboard.

---

## APPENDIX A — Self-Review: Enterprise Additions Confirmed Included
Multi-tenancy/region readiness • Outbox + saga patterns • Double-entry ledger • Idempotency everywhere on money • Masked calling/privacy • DPDP/GDPR data lifecycle • Feature flags + experiments • Audit logging • Fraud/abuse engine • Reconciliation & chargebacks • SLA & incident management • Backup/DR/PITR • Observability (metrics/tracing/logs) • Cost governance • Accessibility & localization • Force-update & maintenance mode • Substitution/return/partial flows • Contracts-first parallel development.

## APPENDIX B — Open Decisions for CTO
| # | Decision | Options |
|---|---|---|
| D1 | State mgmt standard | Riverpod-only vs Riverpod+Bloc hybrid |
| D2 | Cloud provider | AWS vs GCP (doc assumes AWS) |
| D3 | Search | OpenSearch vs Typesense (MVP) |
| D4 | GraphQL BFF for mobile | Yes vs REST-only |
| D5 | Workflow engine | Temporal vs BullMQ-only for MVP |
| D6 | 1P dark-store vs 3P-only at MVP | Capital/ops trade-off |

---
*End of Blueprint v1.0 — zopiqnow.*
