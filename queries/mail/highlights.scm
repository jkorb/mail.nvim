[
  (resent_date_label)
  (resent_from_label)
  (resent_sender_label)
  (resent_to_label)
  (resent_cc_label)
  (resent_bcc_label)
  (resent_msg_id_label)
  (orig_date_label)
  (from_label)
  (sender_label)
  (reply_to_label)
  (to_label)
  (cc_label)
  (bcc_label)
  (message_id_label)
  (in_reply_to_label)
  (references_label)
  (subject_label)
  (comments_label)
  (keywords_label)
  (received_label)
  (return_label)
  (optional_field_label)
] @keyword

[
  (to) (from) (cc) (bcc) (sender) (reply_to)
  (resent_to) (resent_from) (resent_cc) (resent_bcc) (resent_sender)
] @address_field

[(msg_id) (addr_spec)] @markup.link.url
(subject_line) @markup.heading
(display_name) @markup.link.label
(date_time) @string.special
(field_sep) @punctuation.delimiter
(signature) @comment
(body) @spell
(quoted_text) @comment

(quoted_lvl1 (quote_symbol) @markup.heading.1)
(quoted_lvl2 (quote_symbol) @markup.heading.2)
(quoted_lvl3 (quote_symbol) @markup.heading.3)
(quoted_lvl4 (quote_symbol) @markup.heading.4)
(quoted_lvl5 (quote_symbol) @markup.heading.5)
(quoted_lvl6 (quote_symbol) @markup.heading.6)
