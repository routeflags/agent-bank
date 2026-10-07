class Mercury::ImagesController < MercuryController

  # POST /images.json
  def create
    image = MercuryImage.new(params.require(:image).permit(:image))
    image.save

    respond_to do |format|
      format.json { render json: image }
    end
  rescue StandardError => e
    # 不正なペイロードで Paperclip が例外を送出しても500にせずJSONで応答する
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end
end
