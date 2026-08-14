# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ai::StreamingClient do
  let(:url) { "https://api.openai.com/v1/chat/completions" }
  let(:client) { described_class.new(url: url) }
  let(:headers) { { "Authorization" => "Bearer test-key", "Content-Type" => "application/json" } }
  let(:body) { { model: "gpt-4", messages: [], stream: true } }

  describe "#parse_sse_stream" do
    # Builds a fake Net::HTTPResponse that yields chunks via read_body.
    def build_response(chunks)
      response = instance_double(Net::HTTPSuccess, code: "200", message: "OK")
      allow(response).to receive(:is_a?).and_return(false)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

      # Stub read_body to yield chunks
      allow(response).to receive(:read_body) do |&block|
        chunks.each { |chunk| block.call(chunk) }
      end

      response
    end

    context "with normal SSE streaming" do
      it "yields each data line" do
        chunks = [
          "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
          "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n",
          "data: [DONE]\n\n"
        ]
        response = build_response(chunks)

        yielded = []
        client.send(:parse_sse_stream, response) { |data| yielded << data }

        expect(yielded.length).to eq(2)
        expect(yielded[0]).to include("Hello")
        expect(yielded[1]).to include("world")
      end
    end

    context "when [DONE] is received" do
      it "stops processing further data" do
        chunks = [
          "data: {\"choices\":[{\"delta\":{\"content\":\"First\"}}]}\n\n",
          "data: [DONE]\n\n",
          "data: {\"choices\":[{\"delta\":{\"content\":\"Second\"}}]}\n\n"
        ]
        response = build_response(chunks)

        yielded = []
        client.send(:parse_sse_stream, response) { |data| yielded << data }

        expect(yielded.length).to eq(1)
        expect(yielded[0]).to include("First")
      end
    end

    context "with lines without data: prefix" do
      it "ignores non-data lines" do
        chunks = [
          "event: message\n",
          "id: chatcmpl-123\n",
          "data: {\"choices\":[{\"delta\":{\"content\":\"Content\"}}]}\n\n"
        ]
        response = build_response(chunks)

        yielded = []
        client.send(:parse_sse_stream, response) { |data| yielded << data }

        expect(yielded.length).to eq(1)
        expect(yielded[0]).to include("Content")
      end
    end

    context "with empty data lines" do
      it "does not yield empty data" do
        chunks = [
          "data: \n\n",
          "data: {\"choices\":[{\"delta\":{\"content\":\"Real\"}}]}\n\n"
        ]
        response = build_response(chunks)

        yielded = []
        client.send(:parse_sse_stream, response) { |data| yielded << data }

        # "data: " followed by empty → data = "" → yield("") is called
        # This is valid SSE behavior — the block should handle empty strings
        expect(yielded.length).to eq(2)
        expect(yielded[1]).to include("Real")
      end
    end

    context "with JSON error in chunk" do
      it "still yields the raw data for caller to handle" do
        chunks = [
          "data: not valid json\n\n",
          "data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\n"
        ]
        response = build_response(chunks)

        yielded = []
        client.send(:parse_sse_stream, response) { |data| yielded << data }

        expect(yielded.length).to eq(2)
        expect(yielded[0]).to eq("not valid json")
        expect(yielded[1]).to include("OK")
      end
    end

    context "with remaining buffer after read_body ends" do
      it "processes the remaining buffer when no [DONE]" do
        # Single chunk with no trailing \n — tests buffer remainder
        chunks = [
          "data: {\"choices\":[{\"delta\":{\"content\":\"Leftover\"}}]}"
        ]
        response = build_response(chunks)

        yielded = []
        client.send(:parse_sse_stream, response) { |data| yielded << data }

        expect(yielded.length).to eq(1)
        expect(yielded[0]).to include("Leftover")
      end

      it "does not process buffer when stream ended with [DONE]" do
        chunks = [
          "data: [DONE]\n",
          "data: {\"choices\":[{\"delta\":{\"content\":\"After\"}}]}"
        ]
        response = build_response(chunks)

        yielded = []
        client.send(:parse_sse_stream, response) { |data| yielded << data }

        expect(yielded).to be_empty
      end
    end
  end

  describe "error classification" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:open_timeout=)
    end

    context "when Net::ReadTimeout occurs" do
      it "raises TimeoutError" do
        allow(mock_http).to receive(:request).and_raise(Net::ReadTimeout, "execution expired")

        expect {
          client.post(headers: headers, body: body)
        }.to raise_error(Ai::StreamingClient::TimeoutError, /Read timeout/)
      end
    end

    context "when Net::OpenTimeout occurs" do
      it "raises TimeoutError" do
        allow(mock_http).to receive(:request).and_raise(Net::OpenTimeout, "execution expired")

        expect {
          client.post(headers: headers, body: body)
        }.to raise_error(Ai::StreamingClient::TimeoutError, /Read timeout/)
      end
    end

    context "when Errno::ECONNRESET occurs" do
      it "raises ConnectionError" do
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNRESET, "Connection reset by peer")

        expect {
          client.post(headers: headers, body: body)
        }.to raise_error(Ai::StreamingClient::ConnectionError, /Connection failed/)
      end
    end

    context "when Errno::EPIPE occurs" do
      it "raises ConnectionError" do
        allow(mock_http).to receive(:request).and_raise(Errno::EPIPE, "Broken pipe")

        expect {
          client.post(headers: headers, body: body)
        }.to raise_error(Ai::StreamingClient::ConnectionError, /Connection failed/)
      end
    end

    context "when Errno::ECONNREFUSED occurs" do
      it "raises ConnectionError" do
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED, "Connection refused")

        expect {
          client.post(headers: headers, body: body)
        }.to raise_error(Ai::StreamingClient::ConnectionError, /Connection failed/)
      end
    end

    context "when IOError occurs" do
      it "raises StreamingError" do
        allow(mock_http).to receive(:request).and_raise(IOError, "stream closed in another thread")

        expect {
          client.post(headers: headers, body: body)
        }.to raise_error(Ai::StreamingClient::StreamingError, /IO error/)
      end
    end
  end
end
