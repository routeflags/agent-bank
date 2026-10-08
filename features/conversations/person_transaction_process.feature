Feature: Transaction process between two users

  @javascript
  Scenario: Free message conversation for non-monetary transaction
    Given community "test" has country "US" and currency "USD"
    Given there are following users:
      | person |
      | kassi_testperson1 |
      | kassi_testperson2 |
      | kassi_testperson3 |
    And "kassi_testperson3" is superadmin
    And there is a free listing with title "Hammer" from "kassi_testperson1" with category "Items" and with listing shape "Requesting"
    And I am logged in as "kassi_testperson2"

    # Starting the conversation (raku: free conversations go through the
    # Contact button on the listing page; the old "Offer" preauthorize UI
    # only appears for paid listings)
    When I follow the first "Hammer"
    And I follow "💬 Contact the seller"
    And I fill in "Message" with "I can lend this item"
    And I press "Send message"
    And the system processes jobs
    And "kassi_testperson1@example.com" should receive an email
    And I log out

    # Replying
    When I open the email
    And I follow "Click here to reply to Kassi" in the email
    And I log in as "kassi_testperson1"
    And I fill in "message[content]" with "Ok, that works!"
    And I press "Send reply"
    Then I should see "Ok, that works!" in the message list
    And the system processes jobs
    Then "kassi_testperson2@example.com" should receive an email
    And I log out

    # Admin sees free transaction with proper currency
    When I log in as "kassi_testperson3"
    And I am on the transactions admin2 page
    Then I should see "$0"
    And I should not see "€0"
