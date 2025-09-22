;; Heritage Site Registry
;; Manages registration, verification, and metadata of heritage sites

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-SITE-NOT-FOUND (err u404))
(define-constant ERR-SITE-ALREADY-EXISTS (err u409))
(define-constant ERR-INVALID-CAPACITY (err u400))
(define-constant ERR-SITE-NOT-VERIFIED (err u403))
(define-constant ERR-INSUFFICIENT-STAKE (err u402))
(define-constant ERR-ALREADY-VERIFIED (err u410))
(define-constant ERR-INVALID-RATING (err u411))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-VERIFICATION-STAKE u1000000) ;; 1 STX in microSTX

;; Data Variables
(define-data-var site-counter uint u0)
(define-data-var total-revenue uint u0)

;; Data Maps
(define-map heritage-sites
  uint ;; site-id
  {
    name: (string-ascii 100),
    description: (string-utf8 500),
    location: {lat: int, lng: int}, ;; coordinates in millionths of degrees
    category: (string-ascii 50),
    established-date: uint, ;; block height
    max-daily-visitors: uint,
    current-visitors: uint,
    total-visits: uint,
    rating: uint, ;; average rating * 100 (e.g., 450 = 4.5 stars)
    rating-count: uint,
    revenue-generated: uint,
    is-verified: bool,
    is-active: bool,
    owner: principal,
    verification-stake: uint
  }
)

(define-map site-verifications
  uint ;; site-id
  {
    verifier: principal,
    stake-amount: uint,
    verification-date: uint,
    verification-notes: (string-utf8 200)
  }
)

(define-map user-visits
  {user: principal, site-id: uint}
  {
    visit-count: uint,
    last-visit: uint,
    total-spent: uint,
    has-reviewed: bool
  }
)

(define-map site-reviews
  {site-id: uint, reviewer: principal}
  {
    rating: uint, ;; 1-5 stars
    review: (string-utf8 300),
    visit-date: uint,
    helpful-votes: uint
  }
)

(define-map daily-visitors
  {site-id: uint, date: uint} ;; date as block height / 144 (approx daily)
  uint ;; visitor count
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-site-owner (site-id uint))
  (match (map-get? heritage-sites site-id)
    site-data (is-eq tx-sender (get owner site-data))
    false
  )
)

(define-private (get-daily-date)
  (/ block-height u144) ;; Approximate blocks per day
)

(define-private (update-site-rating (site-id uint) (new-rating uint))
  (match (map-get? heritage-sites site-id)
    site-data
    (let (
      (current-total (* (get rating site-data) (get rating-count site-data)))
      (new-count (+ (get rating-count site-data) u1))
      (new-average (/ (+ current-total new-rating) new-count))
    )
    (map-set heritage-sites site-id
      (merge site-data {
        rating: new-average,
        rating-count: new-count
      })
    )
    true
    )
    false
  )
)

;; Public Functions

;; Register a new heritage site
(define-public (register-site 
  (name (string-ascii 100))
  (description (string-utf8 500))
  (location {lat: int, lng: int})
  (category (string-ascii 50))
  (max-daily-visitors uint)
)
  (let (
    (site-id (+ (var-get site-counter) u1))
  )
  (asserts! (> max-daily-visitors u0) ERR-INVALID-CAPACITY)
  (asserts! (> (len name) u0) ERR-INVALID-CAPACITY)
  
  (map-set heritage-sites site-id {
    name: name,
    description: description,
    location: location,
    category: category,
    established-date: block-height,
    max-daily-visitors: max-daily-visitors,
    current-visitors: u0,
    total-visits: u0,
    rating: u0,
    rating-count: u0,
    revenue-generated: u0,
    is-verified: false,
    is-active: true,
    owner: tx-sender,
    verification-stake: u0
  })
  
  (var-set site-counter site-id)
  (ok site-id)
  )
)

;; Verify a heritage site (requires stake)
(define-public (verify-site (site-id uint) (verification-notes (string-utf8 200)))
  (let (
    (site-data (unwrap! (map-get? heritage-sites site-id) ERR-SITE-NOT-FOUND))
  )
  (asserts! (not (get is-verified site-data)) ERR-ALREADY-VERIFIED)
  (asserts! (>= (stx-get-balance tx-sender) MIN-VERIFICATION-STAKE) ERR-INSUFFICIENT-STAKE)
  
  ;; Transfer stake to contract
  (try! (stx-transfer? MIN-VERIFICATION-STAKE tx-sender (as-contract tx-sender)))
  
  ;; Update site verification
  (map-set heritage-sites site-id
    (merge site-data {
      is-verified: true,
      verification-stake: MIN-VERIFICATION-STAKE
    })
  )
  
  ;; Record verification details
  (map-set site-verifications site-id {
    verifier: tx-sender,
    stake-amount: MIN-VERIFICATION-STAKE,
    verification-date: block-height,
    verification-notes: verification-notes
  })
  
  (ok true)
  )
)

;; Record a site visit
(define-public (record-visit (site-id uint) (payment-amount uint))
  (let (
    (site-data (unwrap! (map-get? heritage-sites site-id) ERR-SITE-NOT-FOUND))
    (daily-date (get-daily-date))
    (current-daily-visitors (default-to u0 (map-get? daily-visitors {site-id: site-id, date: daily-date})))
    (user-visit-data (default-to {visit-count: u0, last-visit: u0, total-spent: u0, has-reviewed: false} 
                                 (map-get? user-visits {user: tx-sender, site-id: site-id})))
  )
  (asserts! (get is-active site-data) ERR-SITE-NOT-VERIFIED)
  (asserts! (get is-verified site-data) ERR-SITE-NOT-VERIFIED)
  (asserts! (< current-daily-visitors (get max-daily-visitors site-data)) ERR-INVALID-CAPACITY)
  
  ;; Update site statistics
  (map-set heritage-sites site-id
    (merge site-data {
      total-visits: (+ (get total-visits site-data) u1),
      revenue-generated: (+ (get revenue-generated site-data) payment-amount)
    })
  )
  
  ;; Update daily visitor count
  (map-set daily-visitors {site-id: site-id, date: daily-date}
    (+ current-daily-visitors u1)
  )
  
  ;; Update user visit data
  (map-set user-visits {user: tx-sender, site-id: site-id}
    (merge user-visit-data {
      visit-count: (+ (get visit-count user-visit-data) u1),
      last-visit: block-height,
      total-spent: (+ (get total-spent user-visit-data) payment-amount)
    })
  )
  
  ;; Update total revenue
  (var-set total-revenue (+ (var-get total-revenue) payment-amount))
  
  (ok true)
  )
)

;; Submit a review for a site
(define-public (submit-review 
  (site-id uint) 
  (rating uint) 
  (review (string-utf8 300))
)
  (let (
    (site-data (unwrap! (map-get? heritage-sites site-id) ERR-SITE-NOT-FOUND))
    (user-visit-data (unwrap! (map-get? user-visits {user: tx-sender, site-id: site-id}) ERR-NOT-AUTHORIZED))
  )
  (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
  (asserts! (> (get visit-count user-visit-data) u0) ERR-NOT-AUTHORIZED)
  (asserts! (not (get has-reviewed user-visit-data)) ERR-ALREADY-VERIFIED)
  
  ;; Record the review
  (map-set site-reviews {site-id: site-id, reviewer: tx-sender} {
    rating: rating,
    review: review,
    visit-date: (get last-visit user-visit-data),
    helpful-votes: u0
  })
  
  ;; Update user visit data
  (map-set user-visits {user: tx-sender, site-id: site-id}
    (merge user-visit-data {has-reviewed: true})
  )
  
  ;; Update site rating
  (update-site-rating site-id (* rating u100)) ;; Convert to 100-based scale
  
  (ok true)
  )
)

;; Update site information (owner only)
(define-public (update-site-info 
  (site-id uint) 
  (name (string-ascii 100))
  (description (string-utf8 500))
  (max-daily-visitors uint)
)
  (let (
    (site-data (unwrap! (map-get? heritage-sites site-id) ERR-SITE-NOT-FOUND))
  )
  (asserts! (is-site-owner site-id) ERR-NOT-AUTHORIZED)
  (asserts! (> max-daily-visitors u0) ERR-INVALID-CAPACITY)
  
  (map-set heritage-sites site-id
    (merge site-data {
      name: name,
      description: description,
      max-daily-visitors: max-daily-visitors
    })
  )
  
  (ok true)
  )
)

;; Toggle site active status (owner only)
(define-public (toggle-site-status (site-id uint))
  (let (
    (site-data (unwrap! (map-get? heritage-sites site-id) ERR-SITE-NOT-FOUND))
  )
  (asserts! (is-site-owner site-id) ERR-NOT-AUTHORIZED)
  
  (map-set heritage-sites site-id
    (merge site-data {
      is-active: (not (get is-active site-data))
    })
  )
  
  (ok (not (get is-active site-data)))
  )
)

;; Withdraw site revenue (owner only)
(define-public (withdraw-site-revenue (site-id uint) (amount uint))
  (let (
    (site-data (unwrap! (map-get? heritage-sites site-id) ERR-SITE-NOT-FOUND))
  )
  (asserts! (is-site-owner site-id) ERR-NOT-AUTHORIZED)
  (asserts! (<= amount (get revenue-generated site-data)) ERR-INVALID-CAPACITY)
  
  ;; Transfer STX from contract to site owner
  (try! (as-contract (stx-transfer? amount tx-sender (get owner site-data))))
  
  ;; Update site revenue
  (map-set heritage-sites site-id
    (merge site-data {
      revenue-generated: (- (get revenue-generated site-data) amount)
    })
  )
  
  (ok amount)
  )
)

;; Read-only functions

(define-read-only (get-site-info (site-id uint))
  (map-get? heritage-sites site-id)
)

(define-read-only (get-site-verification (site-id uint))
  (map-get? site-verifications site-id)
)

(define-read-only (get-user-visit-history (user principal) (site-id uint))
  (map-get? user-visits {user: user, site-id: site-id})
)

(define-read-only (get-site-review (site-id uint) (reviewer principal))
  (map-get? site-reviews {site-id: site-id, reviewer: reviewer})
)

(define-read-only (get-daily-visitor-count (site-id uint) (date uint))
  (default-to u0 (map-get? daily-visitors {site-id: site-id, date: date}))
)

(define-read-only (get-total-sites)
  (var-get site-counter)
)

(define-read-only (get-total-revenue)
  (var-get total-revenue)
)

(define-read-only (can-visit-today (site-id uint))
  (match (map-get? heritage-sites site-id)
    site-data
    (let (
      (daily-date (get-daily-date))
      (current-visitors (default-to u0 (map-get? daily-visitors {site-id: site-id, date: daily-date})))
    )
    (and 
      (get is-active site-data)
      (get is-verified site-data)
      (< current-visitors (get max-daily-visitors site-data))
    )
    )
    false
  )
)
