[
  "app/view_utils/listing_form_view_utils",
  "app/services/result"
].each { |file| require_relative "../../#{file}" }

require 'pry'
require 'active_support'
require 'active_support/core_ext/object'

describe ListingFormViewUtils do
  describe "#build_listing_params" do
    let(:shape) do
      OpenStruct.new(
        id: 1,
        transaction_process_id: 2,
        name_tr_key: "listings.listing",
        action_button_tr_key: "listings.show",
        availability: "none",
        price_enabled: false,
        shipping_enabled: false,
        units: []
      )
    end
    let(:community) { double(currency: "JPY", hide_expiration_date: true, id: 3) }
    let(:listing_params) do
      ActionController::Parameters.new(
        listing: {
          title: "AIペルソナ",
          description: "説明",
          unit: ""
        }
      )
    end

    it "実行モードが送信されない新規出品をオンライン実行にする" do
      result = described_class.build_listing_params(shape, "uuid", listing_params, community)

      expect(result.success).to eq(true)
      expect(result.data).to include(
        default_run_mode: "run_online",
        supported_run_modes: ["run_online"]
      )
    end

    it "編集時に指定された既存の実行モードを維持する" do
      result = described_class.build_listing_params(
        shape,
        "uuid",
        listing_params,
        community,
        default_run_mode: "download"
      )

      expect(result.success).to eq(true)
      expect(result.data).to include(
        default_run_mode: "download",
        supported_run_modes: ["download"]
      )
    end

    it "スキル説明 (skill_markdown) を保存パラメータに含める" do
      params = ActionController::Parameters.new(
        listing: {
          title: "AIペルソナ",
          description: "説明",
          unit: "",
          skill_markdown: "- Python\n- 英語会話"
        }
      )

      result = described_class.build_listing_params(shape, "uuid", params, community)

      expect(result.success).to eq(true)
      expect(result.data).to include(skill_markdown: "- Python\n- 英語会話")
    end
  end

  describe "#filter" do
    def expect_filter(params, shape_opts, valid_until_enabled = false)
      shape_defaults = {
        price_enabled: true,
        units: []
      }

      expect(ListingFormViewUtils.filter(
               params,
               shape_defaults.merge(shape_opts),
               valid_until_enabled))
    end

    it "filters fields that do not belong to the shape" do
      expect_filter({price: "50.0"}, {price_enabled: true}).to include(:price)
      expect_filter({price: "50.0"}, {price_enabled: false}).not_to include(:price)

      expect_filter({currency: "EUR"}, {price_enabled: true}).to include(:currency)
      expect_filter({currency: "EUR"}, {price_enabled: false}).not_to include(:currency)

      expect_filter({unit: "day"}, {units: [{type: :day, quantity_selector: :number}]}).to include(:unit)
      expect_filter({unit: "day"}, {units: []}).not_to include(:unit)

      expect_filter({delivery_methods: ["shipping"]}, {shipping_enabled: true}).to include(:delivery_methods)
      expect_filter({delivery_methods: ["shipping"]}, {shipping_enabled: false}).not_to include(:delivery_methods)

      expect_filter({shipping_price: "50.00"}, {shipping_enabled: true}).to include(:shipping_price)
      expect_filter({shipping_price: "50.00"}, {shipping_enabled: false}).not_to include(:shipping_price)

      expect_filter({shipping_price_additional: "50.00"}, {shipping_enabled: true}).to include(:shipping_price_additional)
      expect_filter({shipping_price_additional: "50.00"}, {shipping_enabled: false}).not_to include(:shipping_price_additional)

      expect_filter({"valid_until(1i)" => "2017", "valid_until(2i)" => "6", "valid_until(3i)" => "9"}, {}, false)
        .not_to include("valid_until(1i)", "valid_until(2i)", "valid_until(3i)")

      expect_filter({"valid_until(1i)" => "2017", "valid_until(2i)" => "6", "valid_until(3i)" => "9"}, {}, true)
        .to include("valid_until(1i)", "valid_until(2i)", "valid_until(3i)")
    end
  end

  describe "#validate" do
    def validate(params, shape_opts, unit, valid_until_enabled = false)
      shape_defaults = {
        units: []
      }
      ListingFormViewUtils.validate(
        params: params,
        shape: shape_defaults.merge(shape_opts),
        unit: unit,
        valid_until_enabled: valid_until_enabled
      )
    end

    def expect_valid(params, shape_opts, unit = nil, valid_until_enabled = false)
      validate_res = validate(params, shape_opts, unit, valid_until_enabled)
      expect(validate_res.success).to eq(true), -> {validate_res.data}
    end

    def expect_error(params, shape_opts, errors, unit = nil, valid_until_enabled = false)
      raise ArgumentError.new("Expecting error codes array") if errors.empty?

      res = validate(params, shape_opts, unit, valid_until_enabled)
      expect(res.success).to eq false
      errors.each { |error_code|
        expect(res.data).to include(error_code)
      }
    end

    it "validates the params" do
      expect_valid({price: "50.00", currency: "EUR"}, {price_enabled: true})
      expect_error({price: "50.00"}, {price_enabled: true}, [:currency_required])
      expect_error({currency: "EUR"}, {price_enabled: true}, [:price_required])
      expect_error({}, {price_enabled: true}, [:price_required, :currency_required])

      expect_valid({}, {units: [{type: :day, quantity_selector: :day}]}, {type: :day, quantity_selector: :day})
      expect_valid({}, {units: []})
      expect_error({}, {units: [{type: :day, quantity_selector: :day}]}, [:unit_does_not_belong], {type: :night, quantity_selector: :day})
      expect_error({}, {units: [{type: :day, quantity_selector: :day}]}, [:unit_required])

      expect_valid({delivery_methods: ["shipping", "pickup"]}, {shipping_enabled: true})
      expect_error({delivery_methods: []}, {shipping_enabled: true}, [:delivery_method_required])
      expect_error({delivery_methods: ["homedelivery"]}, {shipping_enabled: true}, [:unknown_delivery_method])

      expect_valid({price: "50.00", currency: "EUR", "valid_until(1i)" => "2017", "valid_until(2i)" => "6", "valid_until(3i)" => "9"},
                   {price_enabled: true},
                   nil,
                   true)

      expect_error({price: "50.00", currency: "EUR"},
                   {price_enabled: true},
                   [:valid_until_missing],
                   nil,
                   true)

      expect_valid({price: "50.00", currency: "EUR"},
                   {price_enabled: true},
                   nil,
                   false)
    end

    it "validates custom units" do
      shape_units = [{:type=>:hour, :quantity_selector=>:number}, {:type=>:custom, :name_tr_key=>"foo", :selector_tr_key=>"bar", :quantity_selector=>:number}]
      req_unit = {:type => :custom,
                  :name_tr_key => "foo",
                  :selector_tr_key => "bar",
                  :quantity_selector => :number}
      expect_valid({}, {units: shape_units}, req_unit)
    end
  end
end

