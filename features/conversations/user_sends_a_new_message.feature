Feature: User sends a new message
  In order to contact another user to ask about details related to a listing or just to chat
  As a user
  I want to be able to send a private message to another users

  @javascript
  Scenario: Sending message from the listing page
    Given there are following users:
      | person |
      | kassi_testperson1 |
      | kassi_testperson2 |
    And community "test" has following listing shapes enabled:
      | listing_shape  | en                | fi             | button  |
      | Inquiry           | Inquiry           | Tiedustelu     | Inquire |
    And community "test" has following category structure:
      | category_type  | en                | fi             |
      | main           | Free message      | Vapaa viesti   |
    And there is a listing with title "Test message" from "kassi_testperson1" with category "Free message" and with listing shape "Inquiry"
    And I am logged in as "kassi_testperson2"
    And I am on the home page
    When I follow the first "Test message"
    And I follow "💬 Contact the seller"
    And I fill in "Message" with "Random message"
    And I press "Send message"
    And I follow inbox link
    Then I should see "Random message"
    And I should not see "Awaiting confirmation from listing author"
    When I log out
    And I log in as "kassi_testperson1"
    And I follow inbox link
    Then I should not see "Accept"
    When I follow "Random message"
    Then I should not see "Accept"