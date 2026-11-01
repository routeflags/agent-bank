# frozen_string_literal: true

module DataImport
  # ドライラン用のバリデーション。
  #
  # このリポジトリの `Person` は `before_validation` の中で `save` を呼ぶ
  # （`set_default_preferences`）ため、新規レコードに `valid?` を呼ぶだけで
  # INSERT が走る。ドライランで書き込みを残さないよう、トランザクション内で
  # `valid?` を実行して必ずロールバックする。
  module DryRun
    module_function

    # @return [Array<String>] エラーメッセージ（空配列なら検証 OK）
    def validate(*records)
      messages = []

      ActiveRecord::Base.transaction do
        records.compact.each do |record|
          record.valid?
          messages.concat(record.errors.full_messages) unless record.errors.empty?
        end

        raise ActiveRecord::Rollback
      end

      messages
    end
  end
end
