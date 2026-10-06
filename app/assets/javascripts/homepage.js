$(function() {
  // Selectors
  var showFiltersButtonSelector = "#home-toolbar-show-filters";
  var filtersContainerSelector = "#home-toolbar-filters";

  // Elements
  var $showFiltersButton = $(showFiltersButtonSelector);
  var $filtersContainer = $(filtersContainerSelector);

  $showFiltersButton.click(function() {
    $showFiltersButton.toggleClass("selected");
    $filtersContainer.toggleClass("home-toolbar-filters-mobile-hidden");
  });

  // Relocate filters
  if ($("#filters").length && $("#desktop-filters").length) {
    relocate(768, $("#filters"), $("#desktop-filters").get(0));
  }

  // The raku header does not render #header-menu-desktop-anchor.
  // Unguarded, relocate() removes the mobile anchor and then throws
  // (undefined destination) inside the jQuery 1.x ready queue, aborting
  // every later ready handler — including the new-listing form's
  // category selector init, which left all options stuck on `.hidden`.
  if ($("#header-menu-mobile-anchor").length && $("#header-menu-desktop-anchor").length) {
    relocate(768, $("#header-menu-mobile-anchor"), $("#header-menu-desktop-anchor").get(0));
  }
  relocate(768, $("#header-user-mobile-anchor"), $("#header-user-desktop-anchor").get(0));
});
