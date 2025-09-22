;; Tour Booking System
;; Facilitates secure booking and payment processing for heritage tours

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-TOUR-NOT-FOUND (err u404))
(define-constant ERR-BOOKING-NOT-FOUND (err u405))
(define-constant ERR-TOUR-FULL (err u406))
(define-constant ERR-TOUR-INACTIVE (err u407))
(define-constant ERR-INVALID-PAYMENT (err u408))
(define-constant ERR-BOOKING-ALREADY-CONFIRMED (err u409))
(define-constant ERR-REFUND-NOT-AVAILABLE (err u410))
(define-constant ERR-TOUR-NOT-COMPLETED (err u411))
(define-constant ERR-ALREADY-REVIEWED (err u412))
(define-constant ERR-INVALID-DATE (err u413))
(define-constant ERR-INSUFFICIENT-BALANCE (err u414))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE-RATE u300) ;; 3% platform fee (basis points)
(define-constant REFUND-WINDOW u1440) ;; 24 hours in blocks (10 min blocks)

;; Data Variables
(define-data-var tour-counter uint u0)
(define-data-var booking-counter uint u0)
(define-data-var platform-revenue uint u0)

;; Data Maps
(define-map tours
  uint ;; tour-id
  {
    title: (string-ascii 100),
    description: (string-utf8 500),
    guide-id: uint,
    site-ids: (list 10 uint), ;; Associated heritage sites
    duration-hours: uint,
    max-participants: uint,
    price-per-person: uint,
    available-dates: (list 50 uint), ;; Available dates as timestamps
    is-active: bool,
    total-bookings: uint,
    average-rating: uint, ;; rating * 100
    rating-count: uint,
    revenue-generated: uint,
    owner: principal,
    created-date: uint
  }
)

(define-map bookings
  uint ;; booking-id
  {
    tour-id: uint,
    tourist: principal,
    participants: uint,
    tour-date: uint, ;; timestamp
    total-amount: uint,
    platform-fee: uint,
    payment-status: (string-ascii 20), ;; "pending", "confirmed", "refunded", "completed"
    booking-date: uint,
    confirmation-code: (string-ascii 20),
    refund-amount: uint,
    is-reviewed: bool
  }
)

(define-map tour-schedules
  {tour-id: uint, date: uint}
  {
    booked-participants: uint,
    bookings: (list 20 uint) ;; booking IDs for this date
  }
)

(define-map tour-reviews
  {tour-id: uint, reviewer: principal}
  {
    booking-id: uint,
    rating: uint, ;; 1-5 stars
    review: (string-utf8 400),
    review-date: uint,
    guide-rating: uint, ;; separate rating for guide
    site-ratings: (list 10 uint) ;; ratings for each site visited
  }
)

(define-map payment-escrow
  uint ;; booking-id
  {
    amount: uint,
    release-date: uint, ;; when funds can be released
    is-released: bool
  }
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-tour-owner (tour-id uint))
  (match (map-get? tours tour-id)
    tour-data (is-eq tx-sender (get owner tour-data))
    false
  )
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE-RATE) u10000)
)

(define-private (generate-confirmation-code (booking-id uint))
  ;; Simple confirmation code generation - just use booking ID
  "BOOK123456789012345" ;; Fixed-length placeholder
)

(define-private (is-date-available (tour-id uint) (tour-date uint) (required-participants uint))
  (let (
    (tour-data (unwrap! (map-get? tours tour-id) false))
    (schedule (default-to {booked-participants: u0, bookings: (list)} 
                          (map-get? tour-schedules {tour-id: tour-id, date: tour-date})))
  )
  (and 
    (get is-active tour-data)
    (<= (+ (get booked-participants schedule) required-participants) (get max-participants tour-data))
    (> tour-date block-height) ;; Tour date must be in the future
  )
  )
)

(define-private (update-tour-rating (tour-id uint) (new-rating uint))
  (match (map-get? tours tour-id)
    tour-data
    (let (
      (current-total (* (get average-rating tour-data) (get rating-count tour-data)))
      (new-count (+ (get rating-count tour-data) u1))
      (new-average (/ (+ current-total new-rating) new-count))
    )
    (map-set tours tour-id
      (merge tour-data {
        average-rating: new-average,
        rating-count: new-count
      })
    )
    true
    )
    false
  )
)

;; Public Functions

;; Create a new tour
(define-public (create-tour 
  (title (string-ascii 100))
  (description (string-utf8 500))
  (guide-id uint)
  (site-ids (list 10 uint))
  (duration-hours uint)
  (max-participants uint)
  (price-per-person uint)
  (available-dates (list 50 uint))
)
  (let (
    (tour-id (+ (var-get tour-counter) u1))
  )
  (asserts! (> max-participants u0) ERR-INVALID-PAYMENT)
  (asserts! (> price-per-person u0) ERR-INVALID-PAYMENT)
  (asserts! (> duration-hours u0) ERR-INVALID-PAYMENT)
  (asserts! (> (len title) u0) ERR-INVALID-PAYMENT)
  (asserts! (> (len site-ids) u0) ERR-INVALID-PAYMENT)
  
  (map-set tours tour-id {
    title: title,
    description: description,
    guide-id: guide-id,
    site-ids: site-ids,
    duration-hours: duration-hours,
    max-participants: max-participants,
    price-per-person: price-per-person,
    available-dates: available-dates,
    is-active: true,
    total-bookings: u0,
    average-rating: u0,
    rating-count: u0,
    revenue-generated: u0,
    owner: tx-sender,
    created-date: block-height
  })
  
  (var-set tour-counter tour-id)
  (ok tour-id)
  )
)

;; Book a tour
(define-public (book-tour (tour-id uint) (participants uint) (tour-date uint))
  (let (
    (tour-data (unwrap! (map-get? tours tour-id) ERR-TOUR-NOT-FOUND))
    (booking-id (+ (var-get booking-counter) u1))
    (total-amount (* (get price-per-person tour-data) participants))
    (platform-fee (calculate-platform-fee total-amount))
    (net-amount (- total-amount platform-fee))
    (confirmation-code (generate-confirmation-code booking-id))
  )
  (asserts! (get is-active tour-data) ERR-TOUR-INACTIVE)
  (asserts! (> participants u0) ERR-INVALID-PAYMENT)
  (asserts! (is-date-available tour-id tour-date participants) ERR-TOUR-FULL)
  (asserts! (>= (stx-get-balance tx-sender) total-amount) ERR-INSUFFICIENT-BALANCE)
  
  ;; Transfer payment to escrow
  (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
  
  ;; Create booking record
  (map-set bookings booking-id {
    tour-id: tour-id,
    tourist: tx-sender,
    participants: participants,
    tour-date: tour-date,
    total-amount: total-amount,
    platform-fee: platform-fee,
    payment-status: "confirmed",
    booking-date: block-height,
    confirmation-code: confirmation-code,
    refund-amount: u0,
    is-reviewed: false
  })
  
  ;; Set up escrow
  (map-set payment-escrow booking-id {
    amount: net-amount,
    release-date: (+ tour-date u144), ;; Release funds 1 day after tour
    is-released: false
  })
  
  ;; Update tour schedule
  (let (
    (current-schedule (default-to {booked-participants: u0, bookings: (list)} 
                                  (map-get? tour-schedules {tour-id: tour-id, date: tour-date})))
  )
  (map-set tour-schedules {tour-id: tour-id, date: tour-date}
    {
      booked-participants: (+ (get booked-participants current-schedule) participants),
      bookings: (unwrap-panic (as-max-len? (append (get bookings current-schedule) booking-id) u20))
    }
  )
  )
  
  ;; Update tour statistics
  (map-set tours tour-id
    (merge tour-data {
      total-bookings: (+ (get total-bookings tour-data) u1)
    })
  )
  
  ;; Update platform revenue
  (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
  
  (var-set booking-counter booking-id)
  (ok {booking-id: booking-id, confirmation-code: confirmation-code})
  )
)

;; Cancel booking and request refund
(define-public (cancel-booking (booking-id uint))
  (let (
    (booking-data (unwrap! (map-get? bookings booking-id) ERR-BOOKING-NOT-FOUND))
    (escrow-data (unwrap! (map-get? payment-escrow booking-id) ERR-BOOKING-NOT-FOUND))
  )
  (asserts! (is-eq tx-sender (get tourist booking-data)) ERR-NOT-AUTHORIZED)
  (asserts! (is-eq (get payment-status booking-data) "confirmed") ERR-BOOKING-ALREADY-CONFIRMED)
  (asserts! (> (get tour-date booking-data) (+ block-height REFUND-WINDOW)) ERR-REFUND-NOT-AVAILABLE)
  
  ;; Calculate refund (90% of total amount to account for processing)
  (let (
    (refund-amount (/ (* (get total-amount booking-data) u9000) u10000))
  )
  ;; Transfer refund
  (try! (as-contract (stx-transfer? refund-amount tx-sender (get tourist booking-data))))
  
  ;; Update booking status
  (map-set bookings booking-id
    (merge booking-data {
      payment-status: "refunded",
      refund-amount: refund-amount
    })
  )
  
  ;; Update tour schedule
  (let (
    (tour-id (get tour-id booking-data))
    (tour-date (get tour-date booking-data))
    (current-schedule (unwrap-panic (map-get? tour-schedules {tour-id: tour-id, date: tour-date})))
  )
  (map-set tour-schedules {tour-id: tour-id, date: tour-date}
    (merge current-schedule {
      booked-participants: (- (get booked-participants current-schedule) (get participants booking-data))
    })
  )
  )
  
  (ok refund-amount)
  )
  )
)

;; Complete tour and release payment
(define-public (complete-tour (booking-id uint))
  (let (
    (booking-data (unwrap! (map-get? bookings booking-id) ERR-BOOKING-NOT-FOUND))
    (tour-data (unwrap! (map-get? tours (get tour-id booking-data)) ERR-TOUR-NOT-FOUND))
    (escrow-data (unwrap! (map-get? payment-escrow booking-id) ERR-BOOKING-NOT-FOUND))
  )
  (asserts! (is-eq tx-sender (get owner tour-data)) ERR-NOT-AUTHORIZED)
  (asserts! (is-eq (get payment-status booking-data) "confirmed") ERR-BOOKING-ALREADY-CONFIRMED)
  (asserts! (>= block-height (get release-date escrow-data)) ERR-TOUR-NOT-COMPLETED)
  (asserts! (not (get is-released escrow-data)) ERR-BOOKING-ALREADY-CONFIRMED)
  
  ;; Release payment to tour owner
  (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender (get owner tour-data))))
  
  ;; Update booking status
  (map-set bookings booking-id
    (merge booking-data {
      payment-status: "completed"
    })
  )
  
  ;; Update escrow status
  (map-set payment-escrow booking-id
    (merge escrow-data {
      is-released: true
    })
  )
  
  ;; Update tour revenue
  (map-set tours (get tour-id booking-data)
    (merge tour-data {
      revenue-generated: (+ (get revenue-generated tour-data) (get amount escrow-data))
    })
  )
  
  (ok (get amount escrow-data))
  )
)

;; Submit tour review
(define-public (submit-tour-review 
  (tour-id uint)
  (booking-id uint)
  (rating uint)
  (review (string-utf8 400))
  (guide-rating uint)
  (site-ratings (list 10 uint))
)
  (let (
    (booking-data (unwrap! (map-get? bookings booking-id) ERR-BOOKING-NOT-FOUND))
    (tour-data (unwrap! (map-get? tours tour-id) ERR-TOUR-NOT-FOUND))
  )
  (asserts! (is-eq tx-sender (get tourist booking-data)) ERR-NOT-AUTHORIZED)
  (asserts! (is-eq (get tour-id booking-data) tour-id) ERR-NOT-AUTHORIZED)
  (asserts! (is-eq (get payment-status booking-data) "completed") ERR-TOUR-NOT-COMPLETED)
  (asserts! (not (get is-reviewed booking-data)) ERR-ALREADY-REVIEWED)
  (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-PAYMENT)
  (asserts! (and (>= guide-rating u1) (<= guide-rating u5)) ERR-INVALID-PAYMENT)
  
  ;; Record the review
  (map-set tour-reviews {tour-id: tour-id, reviewer: tx-sender} {
    booking-id: booking-id,
    rating: rating,
    review: review,
    review-date: block-height,
    guide-rating: guide-rating,
    site-ratings: site-ratings
  })
  
  ;; Update booking review status
  (map-set bookings booking-id
    (merge booking-data {is-reviewed: true})
  )
  
  ;; Update tour rating
  (update-tour-rating tour-id (* rating u100))
  
  (ok true)
  )
)

;; Update tour information (owner only)
(define-public (update-tour-info 
  (tour-id uint)
  (title (string-ascii 100))
  (description (string-utf8 500))
  (price-per-person uint)
  (max-participants uint)
)
  (let (
    (tour-data (unwrap! (map-get? tours tour-id) ERR-TOUR-NOT-FOUND))
  )
  (asserts! (is-tour-owner tour-id) ERR-NOT-AUTHORIZED)
  (asserts! (> price-per-person u0) ERR-INVALID-PAYMENT)
  (asserts! (> max-participants u0) ERR-INVALID-PAYMENT)
  
  (map-set tours tour-id
    (merge tour-data {
      title: title,
      description: description,
      price-per-person: price-per-person,
      max-participants: max-participants
    })
  )
  
  (ok true)
  )
)

;; Toggle tour status (owner only)
(define-public (toggle-tour-status (tour-id uint))
  (let (
    (tour-data (unwrap! (map-get? tours tour-id) ERR-TOUR-NOT-FOUND))
  )
  (asserts! (is-tour-owner tour-id) ERR-NOT-AUTHORIZED)
  
  (map-set tours tour-id
    (merge tour-data {
      is-active: (not (get is-active tour-data))
    })
  )
  
  (ok (not (get is-active tour-data)))
  )
)

;; Read-only functions

(define-read-only (get-tour-info (tour-id uint))
  (map-get? tours tour-id)
)

(define-read-only (get-booking-info (booking-id uint))
  (map-get? bookings booking-id)
)

(define-read-only (get-tour-schedule (tour-id uint) (date uint))
  (map-get? tour-schedules {tour-id: tour-id, date: date})
)

(define-read-only (get-tour-review (tour-id uint) (reviewer principal))
  (map-get? tour-reviews {tour-id: tour-id, reviewer: reviewer})
)

(define-read-only (get-escrow-info (booking-id uint))
  (map-get? payment-escrow booking-id)
)

(define-read-only (get-total-tours)
  (var-get tour-counter)
)

(define-read-only (get-total-bookings)
  (var-get booking-counter)
)

(define-read-only (get-platform-revenue)
  (var-get platform-revenue)
)

(define-read-only (check-availability (tour-id uint) (tour-date uint) (participants uint))
  (is-date-available tour-id tour-date participants)
)
