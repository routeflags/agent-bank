class MessagesController < ApplicationController

  before_action do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_send_a_message")
  end

  before_action EnsureCanAccessPerson.new(:person_id, error_message_key: "layouts.notifications.you_are_not_authorized_to_do_this")

  def create
    unless is_participant?(@current_user, params[:message][:conversation_id])
      flash[:error] = t("layouts.notifications.you_are_not_authorized_to_do_this")
      return redirect_to search_path
    end

    message_params = params.require(:message).permit(
      :conversation_id,
      :content
    ).merge(
      sender_id: @current_user.id
    )

    @message = Message.new(message_params)
    if @message.save
      Delayed::Job.enqueue(MessageSentJob.new(@message.id, @current_community.id))
    else
      # 保存失敗時はビューユーティリティを呼ぶと未保存レコードで例外になるため、
      # そのままリダイレクト/空応答して終了する
      flash[:error] = "reply_cannot_be_empty"
      respond_to do |format|
        format.html { redirect_to single_conversation_path(:conversation_type => "received", :person_id => @current_user.id, :id => params[:message][:conversation_id]) }
        format.js { head :ok }
      end
      return
    end

    message_bubble = TransactionViewUtils.conversation_messages([@message], nil).first

    respond_to do |format|
      format.html { redirect_to single_conversation_path(:conversation_type => "received", :person_id => @current_user.id, :id => params[:message][:conversation_id]) }
      format.js { render :layout => false, locals: { message: message_bubble } }
    end
  end

  private


  def is_participant?(person, conversation_id)
    Conversation.find(conversation_id).participant?(person)
  end

end
