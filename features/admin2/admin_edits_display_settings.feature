Feature: Admin edits design display page

  Background:
    Given "kassi_testperson1" has admin rights in community "test"
    And there is a listing with title "Massage" from "kassi_testperson1" with category "Services" and with listing shape "Requesting"
    And I am logged in as "kassi_testperson1"
    And I go to the admin2 design display community "test"

  @javascript
  Scenario: Admin can change the default listing view to list
    Given community "test" has default browse view "grid"
    When I choose "List"
    And I press submit
    And I wait for 1 seconds
    Then community "test" should have default browse view "list"

  @javascript
  Scenario: Admin can change the name display type to full name (First Last)
    Given community "test" has name display type "first_name_with_initial"
    When I choose "community_name_display_type_full_name"
    And I press submit
    And I wait for 1 seconds
    Then community "test" should have name display type "full_name"

  @javascript
  Scenario: Admin can change to show the listing type
    Given community "test" has default browse view "list"
    When I choose "List"
    And I check "Show listing type in the List view"
    And I wait for 1 seconds
    And I press submit
    And I wait for 1 seconds
    Then the community should show category in listing list

  @javascript
  Scenario: Admin can change to hide the listing type
    Given community "test" has default browse view "list"
    When I choose "List"
    And I uncheck "Show listing type in the List view"
    And I wait for 1 seconds
    And I press submit
    And I wait for 1 seconds
    Then the community should not show category in listing list

  @javascript
  Scenario: Admin can show listing publish date
    When I check "Show listing publishing date on the listing page"
    And I press submit
    And I wait for 1 seconds
    Then the community should show listing publishing date

  @javascript
  Scenario: Admin can hide listing publish date
    When I uncheck "Show listing publishing date on the listing page"
    And I press submit
    And I wait for 1 seconds
    Then the community should not show listing publishing date
