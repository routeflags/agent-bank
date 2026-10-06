# ThinkingSphinx::Deltas::DelayedDelta::DeltaJob

def stub_thinking_sphinx
  allow(ThinkingSphinx::Deltas::DelayedDelta::DeltaJob).to receive(:perform).and_return(true)
  allow(ThinkingSphinx::Deltas::IndexJob).to receive(:perform).and_return(true)
end

# ThinkingSphinx::Test.autostop が登録する終了フックは、searchd の停止に
# 失敗すると Kernel.exit を送出し、スイートのサマリー出力を壊す。
# stop をラップして SystemExit を抑止する。
module SafeSphinxStop
  def stop
    super
  rescue SystemExit
    nil
  end
end

require "thinking_sphinx/test"
ThinkingSphinx::Test.singleton_class.prepend(SafeSphinxStop)


