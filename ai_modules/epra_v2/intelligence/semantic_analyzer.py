"""
semantic_analyzer.py

Handles Semantic Intelligence (SI) for EPRA V2.

Team Ownership Contract:
- Member 3 provides CBIR / Semantic Analysis ONLY FOR IMAGE EVIDENCE (semantic_score).
- Member 3 is NOT the provider for non-image evidence.
- Non-image evidence calculates semantic relevance using actual evidence text content
  and investigation case_context via smoothed TF-IDF cosine similarity.
- Bypasses all filename keyword guessing and type defaults in production.
- If content or case_context is missing/unusable, marked as NOT AVAILABLE / PENDING.
- Heuristic estimation is isolated strictly to explicit demo/test mode.
"""

import collections
import csv
import email
from email import policy
import math
from pathlib import Path
import re
from typing import Optional

from ..utils.config import DEFAULT_DEMO_MODE


class SemanticAnalyzer:
    """
    Semantic Intelligence Handler.
    """

    TOKEN_REGEX = re.compile(r'\b[a-zA-Z0-9_-]{2,}\b')
    STOP_WORDS = {
        "a", "about", "above", "after", "again", "against", "all", "am", "an", "and",
        "any", "are", "aren't", "as", "at", "be", "because", "been", "before", "being",
        "below", "between", "both", "but", "by", "can't", "cannot", "could", "couldn't",
        "did", "didn't", "do", "does", "doesn't", "doing", "don't", "down", "during",
        "each", "few", "for", "from", "further", "had", "hadn't", "has", "hasn't",
        "have", "haven't", "having", "he", "he'd", "he'll", "he's", "her", "here",
        "here's", "hers", "herself", "him", "himself", "his", "how", "how's", "i",
        "i'd", "i'll", "i'm", "i've", "if", "in", "into", "is", "isn't", "it", "it's",
        "its", "itself", "let's", "me", "more", "most", "mustn't", "my", "myself",
        "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other", "ought",
        "our", "ours", "ourselves", "out", "over", "own", "same", "shan't", "she",
        "she'd", "she'll", "she's", "should", "shouldn't", "so", "some", "such",
        "than", "that", "that's", "the", "their", "theirs", "them", "themselves",
        "then", "there", "there's", "these", "they", "they'd", "they'll", "they're",
        "they've", "this", "those", "through", "to", "too", "under", "until", "up",
        "very", "was", "wasn't", "we", "we'd", "we'll", "we're", "we've", "were",
        "weren't", "what", "what's", "when", "when's", "where", "where's", "which",
        "while", "who", "who's", "whom", "why", "why's", "with", "won't", "would",
        "wouldn't", "you", "you'd", "you'll", "you're", "you've", "your", "yours",
        "yourself", "yourselves"
    }

    @staticmethod
    def validate_score(score: float) -> float:
        """
        Ensures semantic score is numeric and bounded between 0.0 and 1.0.
        """
        if not isinstance(score, (int, float)):
            return 0.0

        if score < 0.0:
            return 0.0

        if score > 1.0:
            return 1.0

        return round(float(score), 4)

    @classmethod
    def extract_readable_text(cls, evidence) -> Optional[str]:
        """
        Extracts genuine readable text from an evidence object.
        Returns None if no readable text is available (e.g. binary formats
        without extracted text).
        """
        metadata = getattr(evidence, "metadata", None)
        if not metadata:
            return None

        # 1. Generic supplied text representation
        extracted = getattr(metadata, "extracted_text", None)
        if extracted and isinstance(extracted, str) and extracted.strip():
            return extracted.strip()

        path_str = getattr(metadata, "absolute_path", "")
        if not path_str or not Path(path_str).is_file():
            return None

        file_path = Path(path_str)
        ext = file_path.suffix.lower()
        evidence_type = getattr(metadata, "evidence_type", "UNKNOWN")

        # 2. EMAIL: parse subject + body
        if ext == ".eml" or evidence_type == "EMAIL":
            try:
                with open(file_path, "rb") as f:
                    msg = email.message_from_binary_file(f, policy=policy.default)
                    subject = msg.get("subject", "") or ""
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body += part.get_content() or ""
                    else:
                        body = msg.get_content() if msg.get_content_type() == "text/plain" else ""
                    full_text = f"{subject} {body}".strip()
                    return full_text if full_text else None
            except Exception:
                return None

        # 3. CSV / Spreadsheet
        if ext == ".csv" or (evidence_type == "SPREADSHEET" and ext == ".csv"):
            try:
                rows_text = []
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    reader = csv.reader(f)
                    for row in reader:
                        rows_text.append(" ".join(row))
                text = " ".join(rows_text).strip()
                return text if text else None
            except Exception:
                return None

        # 4. Plain text / logs / documents
        if ext in (".txt", ".log", ".json", ".xml", ".tsv") or (
            evidence_type in ("LOG", "DOCUMENT") and ext in (".txt", ".log")
        ):
            try:
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read().strip()
                    return content if content else None
            except Exception:
                try:
                    with open(file_path, "r", encoding="latin-1", errors="ignore") as f:
                        content = f.read().strip()
                        return content if content else None
                except Exception:
                    return None

        # 5. Non-text containers (PDF, DOCX, XLSX, video, audio, executable)
        # MUST NOT decode raw binary as text; require metadata.extracted_text
        return None

    @classmethod
    def compute_tfidf_similarity(cls, evidence_text: str, case_context: dict) -> float:
        """
        Calculates smoothed TF-IDF cosine similarity between evidence text and case context.

        Formula:
        idf(t) = ln((N + 1) / (df(t) + 1)) + 1   (where N = 2)
        tf(t, d) = 1 + ln(count(t, d)) for count > 0
        weight(t, d) = tf(t, d) * idf(t)
        Cosine Similarity = (w_q . w_d) / (||w_q|| * ||w_d||)
        """
        if not evidence_text or not case_context:
            return 0.0

        desc = case_context.get("description", "") or ""
        keywords = case_context.get("keywords", []) or []
        if isinstance(keywords, list):
            keywords_text = " ".join(str(k) for k in keywords)
        else:
            keywords_text = str(keywords)

        query_text = f"{desc} {keywords_text}".strip()
        if not query_text:
            return 0.0

        # Tokenize and filter stop words
        raw_q_tokens = cls.TOKEN_REGEX.findall(query_text.lower())
        raw_d_tokens = cls.TOKEN_REGEX.findall(evidence_text.lower())

        q_tokens = [t for t in raw_q_tokens if t not in cls.STOP_WORDS]
        d_tokens = [t for t in raw_d_tokens if t not in cls.STOP_WORDS]

        if not q_tokens or not d_tokens:
            return 0.0

        q_counts = collections.Counter(q_tokens)
        d_counts = collections.Counter(d_tokens)

        vocab = set(q_counts.keys()) | set(d_counts.keys())
        N = 2

        # Compute weights
        w_q = {}
        w_d = {}

        for term in vocab:
            df = (1 if term in q_counts else 0) + (1 if term in d_counts else 0)
            idf = math.log((N + 1) / (df + 1)) + 1.0

            if term in q_counts:
                tf_q = 1.0 + math.log(q_counts[term])
                w_q[term] = tf_q * idf
            else:
                w_q[term] = 0.0

            if term in d_counts:
                tf_d = 1.0 + math.log(d_counts[term])
                w_d[term] = tf_d * idf
            else:
                w_d[term] = 0.0

        dot_product = sum(w_q[t] * w_d[t] for t in vocab)
        norm_q = math.sqrt(sum(val * val for val in w_q.values()))
        norm_d = math.sqrt(sum(val * val for val in w_d.values()))

        if norm_q == 0.0 or norm_d == 0.0:
            return 0.0

        similarity = dot_product / (norm_q * norm_d)
        return cls.validate_score(similarity)

    @classmethod
    def estimate_semantic_relevance(cls, evidence) -> float:
        """
        DEMO/TEST ONLY:
        Estimates content relevance heuristic based on metadata keywords
        when external CBIR score is not supplied.
        This must NEVER be used in production.
        """
        metadata = getattr(evidence, "metadata", None)
        if not metadata:
            return 0.50

        filename = (getattr(metadata, "file_name", "") or "").lower()
        evidence_type = getattr(metadata, "evidence_type", "UNKNOWN")

        high_relevance_keywords = {
            "wallet": 0.94,
            "credential": 0.92,
            "password": 0.90,
            "phishing": 0.88,
            "ransomware": 0.90,
            "malware": 0.88,
            "statement": 0.85,
            "transaction": 0.82,
            "crime": 0.78,
            "cctv": 0.75,
            "activity": 0.65,
            "log": 0.60
        }

        for kw, val in high_relevance_keywords.items():
            if kw in filename:
                return val

        type_defaults = {
            "IMAGE": 0.70,
            "VIDEO": 0.70,
            "EMAIL": 0.75,
            "DOCUMENT": 0.70,
            "SPREADSHEET": 0.65,
            "DATABASE": 0.75,
            "EXECUTABLE": 0.70,
            "LOG": 0.55
        }
        return type_defaults.get(evidence_type, 0.50)

    @classmethod
    def process(
        cls,
        evidence,
        demo_mode: Optional[bool] = None,
        case_context: Optional[dict] = None
    ):
        """
        Updates Semantic Intelligence on Evidence object.

        Contracts:
        - IMAGE Evidence: Consumes Member 3's semantic_score exclusively.
          If unsupplied in production, marked as:
          MISSING EXTERNAL INPUT / INTEGRATION PENDING (Member 3 — IMAGE CBIR/Semantic)
        - NON-IMAGE Evidence:
          Computes smoothed TF-IDF cosine similarity using actual evidence content
          and investigation case_context.
          If content or case_context is missing, marked as:
          NOT AVAILABLE / INTEGRATION PENDING (Non-Image Evidence)
        - Demo Mode: Employs isolated demo heuristic for offline testing if no input is available.
        """
        if demo_mode is None:
            demo_mode = DEFAULT_DEMO_MODE

        evidence_type = getattr(evidence.metadata, "evidence_type", "UNKNOWN")
        is_image = (evidence_type == "IMAGE")

        # -------------------------------------------------------------
        # IMAGE EVIDENCE: Member 3 Contract
        # -------------------------------------------------------------
        if is_image:
            supplied_score = getattr(evidence, "semantic_score", None)
            if supplied_score is not None and isinstance(supplied_score, (int, float)) and supplied_score > 0.0:
                evidence.semantic_intelligence = cls.validate_score(supplied_score)
                if hasattr(evidence, "pending_external_inputs"):
                    evidence.pending_external_inputs.pop("SI", None)
                return evidence

            if demo_mode:
                evidence.semantic_intelligence = cls.validate_score(
                    cls.estimate_semantic_relevance(evidence)
                )
                return evidence

            evidence.semantic_intelligence = 0.0
            if not hasattr(evidence, "pending_external_inputs"):
                evidence.pending_external_inputs = {}
            evidence.pending_external_inputs["SI"] = (
                "MISSING EXTERNAL INPUT / INTEGRATION PENDING (Member 3 — IMAGE CBIR/Semantic)"
            )
            return evidence

        # -------------------------------------------------------------
        # NON-IMAGE EVIDENCE: Content-Based TF-IDF Similarity
        # -------------------------------------------------------------
        readable_text = cls.extract_readable_text(evidence)

        if readable_text and case_context:
            sim_score = cls.compute_tfidf_similarity(readable_text, case_context)
            evidence.semantic_intelligence = sim_score
            # Analysis succeeded; remove SI from pending even if sim_score is 0.0 (measured zero)
            if hasattr(evidence, "pending_external_inputs"):
                evidence.pending_external_inputs.pop("SI", None)
            return evidence

        # Fallback for demo mode
        if demo_mode:
            evidence.semantic_intelligence = cls.validate_score(
                cls.estimate_semantic_relevance(evidence)
            )
            return evidence

        # Production mode with missing text or missing case context
        evidence.semantic_intelligence = 0.0
        if not hasattr(evidence, "pending_external_inputs"):
            evidence.pending_external_inputs = {}

        evidence.pending_external_inputs["SI"] = (
            "NOT AVAILABLE / INTEGRATION PENDING (Non-Image Evidence)"
        )
        return evidence