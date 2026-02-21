;; SPDX-License-Identifier: MIT
;; Comment Bank - Machine-Readable Format
;;
;; Structure optimised for:
;; - Programmatic access (search, filter, merge)
;; - Version control (clean diffs)
;; - Import/export between tools
;; - Validation and linting
;;
;; Usage: Load with Guile Scheme or parse with any S-expression reader

(comment-bank
  (metadata
    (id "personal-001")
    (name "Working Comment Bank")
    (owner "tutor")
    (created "2026-01-05")
    (modified "2026-01-05")
    (version "0.1.0")
    (schema-version "1"))

  ;; ==========================================================================
  ;; FRAMEWORK - Opening/closing, overall structure
  ;; ==========================================================================
  (category framework
    (meta
      (description "Structural comments: greetings, sign-offs, overall framing")
      (colour "#4a9e4a"))

    (comment
      (id "fw-001")
      (tags greeting opening)
      (text "Thank you for your submission. I've read through your work and have the following feedback."))

    (comment
      (id "fw-002")
      (tags greeting opening personalised)
      (template "Hi {student-name}, thank you for submitting {tma}. {overall-impression}"))

    (comment
      (id "fw-003")
      (tags closing encouragement)
      (text "Overall, this is a solid piece of work. Keep up the good effort."))

    (comment
      (id "fw-004")
      (tags closing next-steps)
      (text "Please review the specific feedback below and feel free to ask questions on the forum if anything is unclear."))

    (comment
      (id "fw-005")
      (tags closing signature)
      (template "Best regards,\n{tutor-name}\n{module} Tutor")))

  ;; ==========================================================================
  ;; MARGIN - Annotations for document margins
  ;; ==========================================================================
  (category margin
    (meta
      (description "Short annotations placed in document margins")
      (colour "#e6a23c"))

    (comment
      (id "mg-001")
      (tags positive)
      (text "Good point"))

    (comment
      (id "mg-002")
      (tags positive)
      (text "Well explained"))

    (comment
      (id "mg-003")
      (tags positive)
      (text "Excellent example"))

    (comment
      (id "mg-004")
      (tags concern clarity)
      (text "Unclear - please expand"))

    (comment
      (id "mg-005")
      (tags concern reference)
      (text "Source needed"))

    (comment
      (id "mg-006")
      (tags concern accuracy)
      (text "Check this"))

    (comment
      (id "mg-007")
      (tags query)
      (text "What do you mean here?"))

    (comment
      (id "mg-008")
      (tags structure)
      (text "Link to previous point")))

  ;; ==========================================================================
  ;; INLINE - Insertions within student text
  ;; ==========================================================================
  (category inline
    (meta
      (description "Comments inserted inline within the student's answer")
      (colour "#409eff"))

    (comment
      (id "in-001")
      (tags reference harvard)
      (text "Please use Harvard referencing format: (Author, Year)."))

    (comment
      (id "in-002")
      (tags reference missing)
      (text "[Reference needed to support this claim]"))

    (comment
      (id "in-003")
      (tags clarity rephrase)
      (text "[Consider rephrasing for clarity]"))

    (comment
      (id "in-004")
      (tags technical term)
      (text "[Technical term - define on first use]"))

    (comment
      (id "in-005")
      (tags grammar)
      (text "[Check grammar/spelling here]"))

    (comment
      (id "in-006")
      (tags logic)
      (text "[The connection here isn't clear - how does this follow?]"))

    (comment
      (id "in-007")
      (tags evidence)
      (text "[Good point - strengthen with specific evidence]")))

  ;; ==========================================================================
  ;; SUMMARY - Overall/section summaries
  ;; ==========================================================================
  (category summary
    (meta
      (description "Longer comments for overall or section summaries")
      (colour "#9c27b0"))

    (comment
      (id "sm-001")
      (tags positive overall)
      (text "You demonstrate a clear understanding of the key concepts. Your explanations are accurate and well-structured."))

    (comment
      (id "sm-002")
      (tags development depth)
      (text "While you've covered the basics well, try to go deeper in your analysis. Ask yourself 'why' and 'how' to develop your points further."))

    (comment
      (id "sm-003")
      (tags structure organisation)
      (text "The structure of your answer could be improved. Consider using headings to organise your response around the question's sub-parts."))

    (comment
      (id "sm-004")
      (tags referencing pattern)
      (text "Your referencing needs attention throughout. Remember: every claim from an external source needs a citation, and all citations need a full reference in your bibliography."))

    (comment
      (id "sm-005")
      (tags critical-thinking)
      (text "You've described the topic well, but at this level we're looking for critical evaluation. Consider: What are the limitations? What alternatives exist? What evidence supports or contradicts this view?"))

    (comment
      (id "sm-006")
      (tags practical application)
      (text "Good theoretical understanding. To strengthen your work, try to include practical examples that show how these concepts apply in real situations."))

    (comment
      (id "sm-007")
      (tags improvement encouragement)
      (text "This submission shows improvement from your previous work. You've clearly taken the earlier feedback on board. Keep building on this progress.")))

  ;; ==========================================================================
  ;; COLLECTED - Imported from collector tool
  ;; ==========================================================================
  (category collected
    (meta
      (description "Comments collected during marking sessions")
      (colour "#666666")
      (auto-imported #t))

    ;; This section populated by importing from comment-collector exports
    ))
