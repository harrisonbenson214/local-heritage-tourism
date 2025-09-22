;; Local Guide Certification System
;; Manages certification, skill verification, and performance tracking for heritage tour guides

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-GUIDE-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-CERTIFIED (err u405))
(define-constant ERR-INVALID-CERTIFICATION-LEVEL (err u406))
(define-constant ERR-INSUFFICIENT-EXPERIENCE (err u407))
(define-constant ERR-CERTIFICATION-EXPIRED (err u408))
(define-constant ERR-INVALID-RATING (err u409))
(define-constant ERR-ALREADY-REVIEWED (err u410))
(define-constant ERR-INVALID-ENDORSEMENT (err u411))
(define-constant ERR-TRAINING-NOT-FOUND (err u412))
(define-constant ERR-TRAINING-ALREADY-COMPLETED (err u413))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant CERTIFICATION-DURATION u52560) ;; ~1 year in blocks (10 min blocks)
(define-constant MIN-TOURS-FOR-UPGRADE u10)
(define-constant MIN-RATING-FOR-UPGRADE u400) ;; 4.0 stars (out of 500)

;; Certification Levels
(define-constant LEVEL-APPRENTICE u1)
(define-constant LEVEL-CERTIFIED u2)
(define-constant LEVEL-EXPERT u3)
(define-constant LEVEL-MASTER u4)

;; Data Variables
(define-data-var guide-counter uint u0)
(define-data-var training-program-counter uint u0)
(define-data-var total-certified-guides uint u0)

;; Data Maps
(define-map certified-guides
  uint ;; guide-id
  {
    name: (string-ascii 100),
    bio: (string-utf8 500),
    specialties: (list 5 (string-ascii 50)), ;; Areas of expertise
    languages: (list 10 (string-ascii 20)),
    certification-level: uint,
    certification-date: uint,
    expiry-date: uint,
    total-tours: uint,
    completed-tours: uint,
    average-rating: uint, ;; rating * 100
    rating-count: uint,
    total-earnings: uint,
    is-active: bool,
    owner: principal,
    verification-documents: (string-utf8 200), ;; IPFS hash or URL
    community-endorsements: uint
  }
)

(define-map guide-reviews
  {guide-id: uint, reviewer: principal}
  {
    tour-id: uint,
    rating: uint, ;; 1-5 stars
    review: (string-utf8 400),
    review-date: uint,
    professionalism-rating: uint,
    knowledge-rating: uint,
    communication-rating: uint
  }
)

(define-map guide-endorsements
  {guide-id: uint, endorser: principal}
  {
    endorsement: (string-utf8 300),
    endorser-credentials: (string-ascii 100),
    endorsement-date: uint,
    skill-areas: (list 5 (string-ascii 50))
  }
)

(define-map training-programs
  uint ;; program-id
  {
    title: (string-ascii 100),
    description: (string-utf8 500),
    instructor: principal,
    duration-hours: uint,
    skill-areas: (list 5 (string-ascii 50)),
    certification-points: uint,
    max-participants: uint,
    current-participants: uint,
    is-active: bool,
    created-date: uint
  }
)

(define-map guide-training
  {guide-id: uint, program-id: uint}
  {
    enrollment-date: uint,
    completion-date: uint,
    final-score: uint,
    certificate-issued: bool,
    instructor-notes: (string-utf8 200)
  }
)

(define-map certification-requirements
  uint ;; level
  {
    min-tours: uint,
    min-rating: uint,
    required-training-hours: uint,
    min-endorsements: uint,
    experience-years: uint
  }
)

(define-map guide-skills
  uint ;; guide-id
  {
    historical-knowledge: uint, ;; 1-100 score
    cultural-awareness: uint,
    communication-skills: uint,
    safety-knowledge: uint,
    language-proficiency: uint,
    storytelling-ability: uint,
    last-assessment-date: uint
  }
)

;; Initialize certification requirements
(map-set certification-requirements LEVEL-APPRENTICE {
  min-tours: u0,
  min-rating: u0,
  required-training-hours: u8,
  min-endorsements: u1,
  experience-years: u0
})

(map-set certification-requirements LEVEL-CERTIFIED {
  min-tours: u5,
  min-rating: u350, ;; 3.5 stars
  required-training-hours: u20,
  min-endorsements: u2,
  experience-years: u1
})

(map-set certification-requirements LEVEL-EXPERT {
  min-tours: u20,
  min-rating: u400, ;; 4.0 stars
  required-training-hours: u40,
  min-endorsements: u3,
  experience-years: u2
})

(map-set certification-requirements LEVEL-MASTER {
  min-tours: u50,
  min-rating: u450, ;; 4.5 stars
  required-training-hours: u80,
  min-endorsements: u5,
  experience-years: u3
})

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-guide-owner (guide-id uint))
  (match (map-get? certified-guides guide-id)
    guide-data (is-eq tx-sender (get owner guide-data))
    false
  )
)

(define-private (is-certification-expired (guide-id uint))
  (match (map-get? certified-guides guide-id)
    guide-data (> block-height (get expiry-date guide-data))
    true
  )
)

(define-private (calculate-training-hours (guide-id uint))
  ;; This would aggregate training hours from completed programs
  ;; Simplified implementation returns a placeholder
  u40
)

(define-private (meets-certification-requirements (guide-id uint) (level uint))
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) false))
    (requirements (unwrap! (map-get? certification-requirements level) false))
    (training-hours (calculate-training-hours guide-id))
  )
  (and 
    (>= (get completed-tours guide-data) (get min-tours requirements))
    (>= (get average-rating guide-data) (get min-rating requirements))
    (>= training-hours (get required-training-hours requirements))
    (>= (get community-endorsements guide-data) (get min-endorsements requirements))
  )
  )
)

(define-private (update-guide-rating (guide-id uint) (new-rating uint))
  (match (map-get? certified-guides guide-id)
    guide-data
    (let (
      (current-total (* (get average-rating guide-data) (get rating-count guide-data)))
      (new-count (+ (get rating-count guide-data) u1))
      (new-average (/ (+ current-total new-rating) new-count))
    )
    (map-set certified-guides guide-id
      (merge guide-data {
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

;; Apply for guide certification
(define-public (apply-for-certification 
  (name (string-ascii 100))
  (bio (string-utf8 500))
  (specialties (list 5 (string-ascii 50)))
  (languages (list 10 (string-ascii 20)))
  (verification-documents (string-utf8 200))
)
  (let (
    (guide-id (+ (var-get guide-counter) u1))
  )
  (asserts! (> (len name) u0) ERR-INVALID-CERTIFICATION-LEVEL)
  (asserts! (> (len specialties) u0) ERR-INVALID-CERTIFICATION-LEVEL)
  
  (map-set certified-guides guide-id {
    name: name,
    bio: bio,
    specialties: specialties,
    languages: languages,
    certification-level: LEVEL-APPRENTICE,
    certification-date: block-height,
    expiry-date: (+ block-height CERTIFICATION-DURATION),
    total-tours: u0,
    completed-tours: u0,
    average-rating: u0,
    rating-count: u0,
    total-earnings: u0,
    is-active: true,
    owner: tx-sender,
    verification-documents: verification-documents,
    community-endorsements: u0
  })
  
  (map-set guide-skills guide-id {
    historical-knowledge: u50,
    cultural-awareness: u50,
    communication-skills: u50,
    safety-knowledge: u50,
    language-proficiency: u50,
    storytelling-ability: u50,
    last-assessment-date: block-height
  })
  
  (var-set guide-counter guide-id)
  (var-set total-certified-guides (+ (var-get total-certified-guides) u1))
  (ok guide-id)
  )
)

;; Upgrade certification level
(define-public (upgrade-certification (guide-id uint) (target-level uint))
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) ERR-GUIDE-NOT-FOUND))
  )
  (asserts! (is-guide-owner guide-id) ERR-NOT-AUTHORIZED)
  (asserts! (and (>= target-level LEVEL-APPRENTICE) (<= target-level LEVEL-MASTER)) ERR-INVALID-CERTIFICATION-LEVEL)
  (asserts! (> target-level (get certification-level guide-data)) ERR-INVALID-CERTIFICATION-LEVEL)
  (asserts! (meets-certification-requirements guide-id target-level) ERR-INSUFFICIENT-EXPERIENCE)
  (asserts! (not (is-certification-expired guide-id)) ERR-CERTIFICATION-EXPIRED)
  
  (map-set certified-guides guide-id
    (merge guide-data {
      certification-level: target-level,
      certification-date: block-height,
      expiry-date: (+ block-height CERTIFICATION-DURATION)
    })
  )
  
  (ok target-level)
  )
)

;; Submit review for a guide
(define-public (submit-guide-review 
  (guide-id uint)
  (tour-id uint)
  (rating uint)
  (review (string-utf8 400))
  (professionalism-rating uint)
  (knowledge-rating uint)
  (communication-rating uint)
)
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) ERR-GUIDE-NOT-FOUND))
  )
  (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
  (asserts! (and (>= professionalism-rating u1) (<= professionalism-rating u5)) ERR-INVALID-RATING)
  (asserts! (and (>= knowledge-rating u1) (<= knowledge-rating u5)) ERR-INVALID-RATING)
  (asserts! (and (>= communication-rating u1) (<= communication-rating u5)) ERR-INVALID-RATING)
  (asserts! (is-none (map-get? guide-reviews {guide-id: guide-id, reviewer: tx-sender})) ERR-ALREADY-REVIEWED)
  
  ;; Record the review
  (map-set guide-reviews {guide-id: guide-id, reviewer: tx-sender} {
    tour-id: tour-id,
    rating: rating,
    review: review,
    review-date: block-height,
    professionalism-rating: professionalism-rating,
    knowledge-rating: knowledge-rating,
    communication-rating: communication-rating
  })
  
  ;; Update guide rating
  (update-guide-rating guide-id (* rating u100))
  
  (ok true)
  )
)

;; Endorse a guide
(define-public (endorse-guide 
  (guide-id uint)
  (endorsement (string-utf8 300))
  (endorser-credentials (string-ascii 100))
  (skill-areas (list 5 (string-ascii 50)))
)
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) ERR-GUIDE-NOT-FOUND))
  )
  (asserts! (> (len endorsement) u0) ERR-INVALID-ENDORSEMENT)
  (asserts! (> (len skill-areas) u0) ERR-INVALID-ENDORSEMENT)
  (asserts! (is-none (map-get? guide-endorsements {guide-id: guide-id, endorser: tx-sender})) ERR-ALREADY-REVIEWED)
  
  ;; Record the endorsement
  (map-set guide-endorsements {guide-id: guide-id, endorser: tx-sender} {
    endorsement: endorsement,
    endorser-credentials: endorser-credentials,
    endorsement-date: block-height,
    skill-areas: skill-areas
  })
  
  ;; Update endorsement count
  (map-set certified-guides guide-id
    (merge guide-data {
      community-endorsements: (+ (get community-endorsements guide-data) u1)
    })
  )
  
  (ok true)
  )
)

;; Create training program
(define-public (create-training-program 
  (title (string-ascii 100))
  (description (string-utf8 500))
  (duration-hours uint)
  (skill-areas (list 5 (string-ascii 50)))
  (certification-points uint)
  (max-participants uint)
)
  (let (
    (program-id (+ (var-get training-program-counter) u1))
  )
  (asserts! (> (len title) u0) ERR-INVALID-CERTIFICATION-LEVEL)
  (asserts! (> duration-hours u0) ERR-INVALID-CERTIFICATION-LEVEL)
  (asserts! (> max-participants u0) ERR-INVALID-CERTIFICATION-LEVEL)
  
  (map-set training-programs program-id {
    title: title,
    description: description,
    instructor: tx-sender,
    duration-hours: duration-hours,
    skill-areas: skill-areas,
    certification-points: certification-points,
    max-participants: max-participants,
    current-participants: u0,
    is-active: true,
    created-date: block-height
  })
  
  (var-set training-program-counter program-id)
  (ok program-id)
  )
)

;; Enroll in training program
(define-public (enroll-in-training (guide-id uint) (program-id uint))
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) ERR-GUIDE-NOT-FOUND))
    (program-data (unwrap! (map-get? training-programs program-id) ERR-TRAINING-NOT-FOUND))
  )
  (asserts! (is-guide-owner guide-id) ERR-NOT-AUTHORIZED)
  (asserts! (get is-active program-data) ERR-TRAINING-NOT-FOUND)
  (asserts! (< (get current-participants program-data) (get max-participants program-data)) ERR-TRAINING-NOT-FOUND)
  (asserts! (is-none (map-get? guide-training {guide-id: guide-id, program-id: program-id})) ERR-TRAINING-ALREADY-COMPLETED)
  
  ;; Enroll guide in training
  (map-set guide-training {guide-id: guide-id, program-id: program-id} {
    enrollment-date: block-height,
    completion-date: u0,
    final-score: u0,
    certificate-issued: false,
    instructor-notes: u""
  })
  
  ;; Update participant count
  (map-set training-programs program-id
    (merge program-data {
      current-participants: (+ (get current-participants program-data) u1)
    })
  )
  
  (ok true)
  )
)

;; Complete training program
(define-public (complete-training 
  (guide-id uint)
  (program-id uint)
  (final-score uint)
  (instructor-notes (string-utf8 200))
)
  (let (
    (program-data (unwrap! (map-get? training-programs program-id) ERR-TRAINING-NOT-FOUND))
    (training-data (unwrap! (map-get? guide-training {guide-id: guide-id, program-id: program-id}) ERR-TRAINING-NOT-FOUND))
  )
  (asserts! (is-eq tx-sender (get instructor program-data)) ERR-NOT-AUTHORIZED)
  (asserts! (<= final-score u100) ERR-INVALID-RATING)
  (asserts! (is-eq (get completion-date training-data) u0) ERR-TRAINING-ALREADY-COMPLETED)
  
  ;; Mark training as completed
  (map-set guide-training {guide-id: guide-id, program-id: program-id}
    (merge training-data {
      completion-date: block-height,
      final-score: final-score,
      certificate-issued: (>= final-score u70), ;; 70% passing grade
      instructor-notes: instructor-notes
    })
  )
  
  (ok (>= final-score u70))
  )
)

;; Update guide profile
(define-public (update-guide-profile 
  (guide-id uint)
  (bio (string-utf8 500))
  (specialties (list 5 (string-ascii 50)))
  (languages (list 10 (string-ascii 20)))
)
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) ERR-GUIDE-NOT-FOUND))
  )
  (asserts! (is-guide-owner guide-id) ERR-NOT-AUTHORIZED)
  
  (map-set certified-guides guide-id
    (merge guide-data {
      bio: bio,
      specialties: specialties,
      languages: languages
    })
  )
  
  (ok true)
  )
)

;; Record tour completion (called by tour system)
(define-public (record-tour-completion (guide-id uint) (earnings uint))
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) ERR-GUIDE-NOT-FOUND))
  )
  ;; This would typically be called by the tour booking system
  ;; For now, we'll allow the guide to self-report
  (asserts! (is-guide-owner guide-id) ERR-NOT-AUTHORIZED)
  
  (map-set certified-guides guide-id
    (merge guide-data {
      completed-tours: (+ (get completed-tours guide-data) u1),
      total-earnings: (+ (get total-earnings guide-data) earnings)
    })
  )
  
  (ok true)
  )
)

;; Toggle guide active status
(define-public (toggle-guide-status (guide-id uint))
  (let (
    (guide-data (unwrap! (map-get? certified-guides guide-id) ERR-GUIDE-NOT-FOUND))
  )
  (asserts! (is-guide-owner guide-id) ERR-NOT-AUTHORIZED)
  
  (map-set certified-guides guide-id
    (merge guide-data {
      is-active: (not (get is-active guide-data))
    })
  )
  
  (ok (not (get is-active guide-data)))
  )
)

;; Read-only functions

(define-read-only (get-guide-info (guide-id uint))
  (map-get? certified-guides guide-id)
)

(define-read-only (get-guide-review (guide-id uint) (reviewer principal))
  (map-get? guide-reviews {guide-id: guide-id, reviewer: reviewer})
)

(define-read-only (get-guide-endorsement (guide-id uint) (endorser principal))
  (map-get? guide-endorsements {guide-id: guide-id, endorser: endorser})
)

(define-read-only (get-training-program-info (program-id uint))
  (map-get? training-programs program-id)
)

(define-read-only (get-guide-training (guide-id uint) (program-id uint))
  (map-get? guide-training {guide-id: guide-id, program-id: program-id})
)

(define-read-only (get-certification-requirements (level uint))
  (map-get? certification-requirements level)
)

(define-read-only (get-guide-skills (guide-id uint))
  (map-get? guide-skills guide-id)
)

(define-read-only (get-total-guides)
  (var-get total-certified-guides)
)

(define-read-only (get-total-training-programs)
  (var-get training-program-counter)
)

(define-read-only (is-guide-certified (guide-id uint))
  (match (map-get? certified-guides guide-id)
    guide-data
    (and 
      (get is-active guide-data)
      (not (is-certification-expired guide-id))
    )
    false
  )
)

(define-read-only (can-upgrade-certification (guide-id uint) (target-level uint))
  (and 
    (is-some (map-get? certified-guides guide-id))
    (meets-certification-requirements guide-id target-level)
    (not (is-certification-expired guide-id))
  )
)
