# frozen_string_literal: true

# == Schema Information
#
# Table name: credit_transactions
#
#  id               :integer          not null, primary key
#  wallet_id        :integer          not null
#  transaction_type :string(255)      not null
#  amount_cents     :decimal(14, 2)   not null
#  reference_type   :string(255)
#  reference_id     :integer
#  metadata         :text(65535)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_credit_transactions_on_reference_type_and_reference_id  (reference_type,reference_id)
#  index_credit_transactions_on_transaction_type                 (transaction_type)
#  index_credit_transactions_on_type_and_reference_unique        (transaction_type,reference_type,reference_id) UNIQUE
#  index_credit_transactions_on_wallet_id                        (wallet_id)
#

class CreditTransaction < ApplicationRecord
  belongs_to :wallet

  # Transaction types:
  #   topup            — manual or automated deposit
  #   usage_deduction  — charged for AI usage (negative amount_cents)
  #   auto_recharge    — triggered by threshold check (positive amount_cents)
  #   refund           — reversal of a previous charge
  #   seller_earning   — revenue share credited to the seller's wallet
  #                      (positive amount_cents, reference: UsageRecord).
  #                      Unique per (transaction_type, reference_type,
  #                      reference_id): one payout per usage event.
end
