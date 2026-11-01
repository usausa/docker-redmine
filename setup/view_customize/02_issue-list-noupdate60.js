$(function() { 
  $('.updated_on').each(function() {
    var currentDate = new Date();
    var startDate = new Date($(this).text());
    var timeDiff = currentDate - startDate;
    var dayDiff = Math.floor(timeDiff / (1000 * 60 * 60 * 24));
    if (dayDiff > 60) {
      $(this).closest('tr').addClass('noupdate60');
    }
  });
});
