import unittest

from src.design_system import COLORS, get_day_card_html


class DayCardHtmlTests(unittest.TestCase):
    def test_day_card_marks_today_state(self):
        html_output = get_day_card_html(
            day_label="THU",
            date_label="02/05",
            emoji="💪",
            title="BACK",
            subtitle="Detail",
            is_today=True,
            is_completed=False,
            color_scheme=COLORS,
        )
        self.assertIn('class="day-card today"', html_output)
        self.assertIn('border: 2px solid', html_output)
        self.assertIn("○", html_output)

    def test_day_card_escapes_text_content(self):
        html_output = get_day_card_html(
            day_label="<TUE>",
            date_label="02/03",
            emoji="💪",
            title="ARMS<script>",
            subtitle="Aesthetics & Form",
            is_today=False,
            is_completed=True,
            color_scheme=COLORS,
        )
        self.assertIn("&lt;TUE&gt;", html_output)
        self.assertIn("ARMS&lt;script&gt;", html_output)
        self.assertIn("Aesthetics &amp; Form", html_output)
        self.assertIn("✓", html_output)


if __name__ == "__main__":
    unittest.main()
