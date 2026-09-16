import os
import sys
import ast
import unittest
import numpy as np

BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROJECT_ROOT = os.path.abspath(os.path.join(BACKEND_DIR, ".."))
CBIR_DIR = os.path.join(PROJECT_ROOT, "ai_modules", "cbir")

for p in [BACKEND_DIR, PROJECT_ROOT, CBIR_DIR]:
    if p not in sys.path:
        sys.path.insert(0, p)

import similarity
from similarity import (
    compute_multi_signal_similarity,
    classify_match,
    compute_confidence_level,
    compute_investigation_recommendation,
    is_verification_required,
    semantic_score,
    WEIGHT_EDGE, WEIGHT_ORB, WEIGHT_HIST, WEIGHT_GRAY,
    VERY_STRONG_MATCH_THRESHOLD, STRONG_MATCH_THRESHOLD,
    POSSIBLE_MATCH_THRESHOLD, WEAK_MATCH_THRESHOLD
)
from semantic_score import compute_semantic_score


class TestCBIRTrishaStandalone(unittest.TestCase):
    """
    Unit test suite validating Trisha's CBIR algorithmic integrity, formulas,
    conservative forensic guardrails, and anti-hardcoding compliance.
    """

    def test_01_weighted_visual_formula_and_constants(self):
        """Verify the exact locked weights: Edge 35%, ORB 25%, Color 20%, Grayscale 20%."""
        self.assertAlmostEqual(WEIGHT_EDGE, 0.35, places=3)
        self.assertAlmostEqual(WEIGHT_ORB, 0.25, places=3)
        self.assertAlmostEqual(WEIGHT_HIST, 0.20, places=3)
        self.assertAlmostEqual(WEIGHT_GRAY, 0.20, places=3)
        total_weights = WEIGHT_EDGE + WEIGHT_ORB + WEIGHT_HIST + WEIGHT_GRAY
        self.assertAlmostEqual(total_weights, 1.00, places=3)
        print("  [PASS] Test 1: Locked weights verified (0.35 Edge + 0.25 ORB + 0.20 Color + 0.20 Grayscale = 1.00).")

    def test_02_exact_duplicate_sha_only(self):
        """Verify Exact Duplicate is produced ONLY when SHA-256 matches cryptographically."""
        # 1. Exact hash match
        cls_exact = classify_match(1.0, is_exact_hash_match=True)
        conf_exact = compute_confidence_level(1.0, is_exact_hash_match=True)
        rec_exact = compute_investigation_recommendation(classification=cls_exact, is_exact_hash_match=True)
        ver_req_exact = is_verification_required(1.0, is_exact_hash_match=True)

        self.assertEqual(cls_exact, "Exact Duplicate")
        self.assertEqual(conf_exact, "High")
        self.assertEqual(rec_exact, "KEEP_FOR_INVESTIGATION")
        self.assertFalse(ver_req_exact, "Exact duplicate MUST NOT require manual verification (Verification Required = No)")

        # 2. Perfect visual similarity score without hash match must NEVER be Exact Duplicate
        cls_visual = classify_match(1.0, is_exact_hash_match=False)
        self.assertNotEqual(cls_visual, "Exact Duplicate", "Visual score alone must NEVER produce Exact Duplicate")
        self.assertEqual(cls_visual, "Very Strong Visual Match")
        self.assertTrue(is_verification_required(1.0, is_exact_hash_match=False), "Visual match requires verification")
        print("  [PASS] Test 2: Exact Duplicate produced exclusively via cryptographic SHA-256.")

    def test_03_classification_tiers(self):
        """Verify conservative match classification tiers."""
        self.assertEqual(classify_match(0.95, is_exact_hash_match=False), "Very Strong Visual Match")
        self.assertEqual(classify_match(0.87, is_exact_hash_match=False), "Strong Visual Match")
        self.assertEqual(classify_match(0.75, is_exact_hash_match=False), "Possible Visual Resemblance")
        self.assertEqual(classify_match(0.55, is_exact_hash_match=False), "Weak Visual Resemblance")
        self.assertEqual(classify_match(0.40, is_exact_hash_match=False), "No Significant Visual Match")
        print("  [PASS] Test 3: Match classifications strictly match approved forensic categories.")

    def test_04_verification_required_rules(self):
        """Verify Section 12 verification_required rules."""
        # Exact Duplicate -> No (False)
        self.assertFalse(is_verification_required(1.0, is_exact_hash_match=True))
        # Very Strong Visual Match -> Yes (True)
        self.assertTrue(is_verification_required(0.95, is_exact_hash_match=False))
        # Strong Visual Match -> Yes (True)
        self.assertTrue(is_verification_required(0.85, is_exact_hash_match=False))
        # Possible Visual Resemblance -> Yes (True)
        self.assertTrue(is_verification_required(0.70, is_exact_hash_match=False))
        # Weak Visual Resemblance -> Yes (True)
        self.assertTrue(is_verification_required(0.50, is_exact_hash_match=False))
        # No Significant Visual Match -> Yes (True for analytical comparisons)
        self.assertTrue(is_verification_required(0.35, is_exact_hash_match=False))
        print("  [PASS] Test 4: Verification required follows approved Section 12 behavior.")

    def test_05_semantic_score_truthful_heuristic(self):
        """Verify Semantic Score is classification-based relevance score without fake AI model."""
        self.assertEqual(compute_semantic_score("Exact Duplicate", 1.0, True), 1.00)
        self.assertEqual(compute_semantic_score("Very Strong Visual Match", 0.95, False), 0.95)
        self.assertEqual(compute_semantic_score("Strong Visual Match", 0.85, False), 0.85)
        self.assertEqual(compute_semantic_score("Possible Visual Resemblance", 0.70, False), 0.70)
        self.assertEqual(compute_semantic_score("Weak Visual Resemblance", 0.50, False), 0.50)
        self.assertEqual(compute_semantic_score("No Significant Visual Match", 0.30, False), 0.40)
        print("  [PASS] Test 5: Semantic score is an explainable classification-based relevance score.")

    def test_06_confidence_and_recommendations(self):
        """Verify confidence levels and conservative investigation recommendations."""
        self.assertEqual(compute_confidence_level(0.90), "High")
        self.assertEqual(compute_confidence_level(0.75), "Medium")
        self.assertEqual(compute_confidence_level(0.40), "Low")

        self.assertEqual(compute_investigation_recommendation("Very Strong Visual Match", 0.95), "KEEP_FOR_INVESTIGATION")
        self.assertEqual(compute_investigation_recommendation("Strong Visual Match", 0.85), "KEEP_FOR_INVESTIGATION")
        self.assertEqual(compute_investigation_recommendation("Possible Visual Resemblance", 0.70), "REVIEW_MANUALLY")
        self.assertEqual(compute_investigation_recommendation("Weak Visual Resemblance", 0.55), "LOW_PRIORITY")
        self.assertEqual(compute_investigation_recommendation("No Significant Visual Match", 0.30), "NOT_RECOMMENDED")
        print("  [PASS] Test 6: Confidence and recommendation mappings verified.")

    def test_07_false_positive_structural_guardrails(self):
        """Verify that edge/ORB structural safeguards prevent pure color agreement from dominating."""
        # Synthesize a feature vector with zero edges/ORB and identical color
        dim = 110464
        f1 = np.zeros(dim, dtype=np.float32)
        f2 = np.zeros(dim, dtype=np.float32)
        # Put matching values in color histogram slice (index 109952 to 110464)
        f1[109952:] = 1.0
        f2[109952:] = 1.0

        score, signals = compute_multi_signal_similarity(f1, f2)
        self.assertTrue(signals["safeguard_applied"], "Safeguard must activate when structural agreement is zero")
        self.assertLessEqual(score, 0.45, "Score must be capped at 0.45 when structural agreement is weak")
        print("  [PASS] Test 7: Structural safeguards successfully capped score on color-only match.")

    def test_08_production_hardcoding_audit(self):
        """Verify production CBIR modules contain zero test fixture hardcoding."""
        forbidden_fixtures = [
            "CASE-1024", "EV-001", "photo1.jpg", "photo2.jpg", "John Doe", "Samsung Galaxy"
        ]
        violations = []
        for f in os.listdir(CBIR_DIR):
            if not f.endswith(".py") or f.startswith("test"):
                continue
            path = os.path.join(CBIR_DIR, f)
            with open(path, "r", encoding="utf-8") as fp:
                tree = ast.parse(fp.read(), filename=path)
            for node in tree.body:
                # Exclude if __name__ == '__main__': blocks
                if isinstance(node, ast.If):
                    test = node.test
                    if isinstance(test, ast.Compare) and isinstance(test.left, ast.Name) and test.left.id == "__name__":
                        continue
                for sub in ast.walk(node):
                    if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
                        for fb in forbidden_fixtures:
                            if fb.lower() in sub.value.lower():
                                violations.append((f, sub.lineno, fb, sub.value[:50]))

        self.assertEqual(len(violations), 0, f"Production code must not contain hardcoded placeholders. Violations: {violations}")
        print("  [PASS] Test 8: AST audit confirms zero placeholder hardcoding in ai_modules/cbir/.")


if __name__ == "__main__":
    print("=" * 70)
    print("RUNNING TRISHA CBIR STANDALONE UNIT TESTS")
    print("=" * 70)
    unittest.main(verbosity=2)
