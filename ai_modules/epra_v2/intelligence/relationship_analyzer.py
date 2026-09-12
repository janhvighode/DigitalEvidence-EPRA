"""
relationship_analyzer.py

Handles suspect entity extraction, relationship correlation, and possible suspect
detection for EPRA V2.

Team Ownership Contract:
- Extracts real identifiers from actual evidence content (emails, IPv4, crypto wallets,
  account IDs).
- Type-aware normalization preserves address representations and case where appropriate.
- Transaction/reference IDs (TXN, TRX, INV, REF) are separated for correlation only
  and do NOT create suspect candidates or inflate Suspect Factor (SF).
- Possible suspect candidates use the identifier itself as the display identity;
  no fictitious human names (Rahul, Amit, Alice) are ever invented in production.
- Demo-only sample identities remain strictly isolated behind demo_mode=True.
"""

import email
from email import policy
import hashlib
import ipaddress
from pathlib import Path
import re
from typing import Optional

from ..models.suspect import Suspect
from ..utils.config import DEFAULT_DEMO_MODE


class RelationshipAnalyzer:
    """
    Extracts and correlates suspect entities and identifiers from digital evidence.
    """

    # Regex patterns for actor-like identifiers (Possible Suspects)
    EMAIL_REGEX = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')
    IPV4_REGEX = re.compile(
        r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
    )
    BITCOIN_BECH32_REGEX = re.compile(r'\bbc1[a-z0-9]{39,59}\b')
    BITCOIN_LEGACY_REGEX = re.compile(r'\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b')
    ETHEREUM_REGEX = re.compile(r'\b0x[a-fA-F0-9]{40}\b')
    ACCOUNT_REGEX = re.compile(r'\b(?:ACC|ACCT)[-_:][A-Za-z0-9]{4,32}\b', re.IGNORECASE)
    IBAN_REGEX = re.compile(r'\bIBAN[-_:]?[A-Z]{2}\d{2}[A-Za-z0-9]{11,30}\b', re.IGNORECASE)

    # Regex patterns for transaction / reference identifiers (correlation only, NOT suspects)
    TRANSACTION_REGEX = re.compile(r'\b(?:TXN|TRX|INV|REF)[-_:][A-Za-z0-9][A-Za-z0-9\-_]{2,31}\b', re.IGNORECASE)

    IGNORED_IPS = {
        "0.0.0.0",
        "255.255.255.255",
        "255.255.255.0",
        "255.255.0.0",
        "255.0.0.0",
        "127.0.0.1"
    }

    @staticmethod
    def normalize_identifier(identifier: str, id_type: str) -> str:
        """
        Type-aware normalization:
        - Email: trim + lowercase
        - IPv4: canonical IP representation
        - Ethereum: lowercase for comparison, preserving original for display
        - Bitcoin: preserve valid address case/representation
        - Account / Transaction: preserve case
        """
        raw = identifier.strip()
        if id_type == "EMAIL":
            return raw.lower()
        elif id_type == "IPV4":
            try:
                return str(ipaddress.IPv4Address(raw))
            except Exception:
                return raw
        elif id_type == "ETHEREUM":
            return raw.lower()
        elif id_type == "BITCOIN":
            return raw
        elif id_type in ("ACCOUNT", "TRANSACTION", "REFERENCE"):
            return raw
        return raw

    @classmethod
    def extract_text_content(cls, evidence) -> str:
        """
        Safely extracts text content from an evidence object.
        Supports:
        - metadata.extracted_text (generic supplied text representation)
        - direct text reading for .eml, .txt, .log, .csv files
        Does NOT decode binary files (PDF, DOCX, XLSX, video, executable) as text.
        """
        metadata = getattr(evidence, "metadata", None)
        if not metadata:
            return ""

        # Check for generic supplied readable text
        extracted_text = getattr(metadata, "extracted_text", None)
        if extracted_text and isinstance(extracted_text, str) and extracted_text.strip():
            return extracted_text

        path_str = getattr(metadata, "absolute_path", "")
        if not path_str or not Path(path_str).is_file():
            return ""

        file_path = Path(path_str)
        ext = file_path.suffix.lower()

        # Parse .eml files
        if ext == ".eml" or getattr(metadata, "evidence_type", "") == "EMAIL":
            try:
                with open(file_path, "rb") as f:
                    msg = email.message_from_binary_file(f, policy=policy.default)
                    subject = msg.get("subject", "")
                    from_header = msg.get("from", "")
                    to_header = msg.get("to", "")
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body += part.get_content() or ""
                    else:
                        body = msg.get_content() if msg.get_content_type() == "text/plain" else ""
                    return f"{from_header}\n{to_header}\n{subject}\n{body}"
            except Exception:
                pass

        # Text-readable formats
        if ext in (".txt", ".log", ".csv", ".json", ".xml"):
            try:
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    return f.read()
            except Exception:
                try:
                    with open(file_path, "r", encoding="latin-1", errors="ignore") as f:
                        return f.read()
                except Exception:
                    return ""

        # Binary formats with no extracted_text supplied
        return ""

    @classmethod
    def extract_actor_identifiers(cls, text: str) -> list[tuple[str, str]]:
        """
        Extracts actor-like identifiers (email, IPv4, crypto, account) that represent
        potential persons/entities of interest.
        Returns list of (id_type, original_identifier).
        """
        if not text:
            return []

        results: list[tuple[str, str]] = []
        seen_keys = set()

        # 1. Emails
        for match in cls.EMAIL_REGEX.findall(text):
            norm = cls.normalize_identifier(match, "EMAIL")
            if ("EMAIL", norm) not in seen_keys:
                seen_keys.add(("EMAIL", norm))
                results.append(("EMAIL", match))

        # 2. IPv4
        for match in cls.IPV4_REGEX.findall(text):
            if match not in cls.IGNORED_IPS:
                norm = cls.normalize_identifier(match, "IPV4")
                if ("IPV4", norm) not in seen_keys:
                    seen_keys.add(("IPV4", norm))
                    results.append(("IPV4", match))

        # 3. Crypto: Bitcoin Bech32 & Legacy
        for match in cls.BITCOIN_BECH32_REGEX.findall(text):
            norm = cls.normalize_identifier(match, "BITCOIN")
            if ("BITCOIN", norm) not in seen_keys:
                seen_keys.add(("BITCOIN", norm))
                results.append(("BITCOIN", match))

        for match in cls.BITCOIN_LEGACY_REGEX.findall(text):
            norm = cls.normalize_identifier(match, "BITCOIN")
            if ("BITCOIN", norm) not in seen_keys:
                seen_keys.add(("BITCOIN", norm))
                results.append(("BITCOIN", match))

        # 4. Crypto: Ethereum
        for match in cls.ETHEREUM_REGEX.findall(text):
            norm = cls.normalize_identifier(match, "ETHEREUM")
            if ("ETHEREUM", norm) not in seen_keys:
                seen_keys.add(("ETHEREUM", norm))
                results.append(("ETHEREUM", match))

        # 5. Accounts / IBAN
        for match in cls.ACCOUNT_REGEX.findall(text):
            norm = cls.normalize_identifier(match, "ACCOUNT")
            if ("ACCOUNT", norm) not in seen_keys:
                seen_keys.add(("ACCOUNT", norm))
                results.append(("ACCOUNT", match))

        for match in cls.IBAN_REGEX.findall(text):
            norm = cls.normalize_identifier(match, "ACCOUNT")
            if ("ACCOUNT", norm) not in seen_keys:
                seen_keys.add(("ACCOUNT", norm))
                results.append(("ACCOUNT", match))

        return results

    @classmethod
    def extract_transaction_identifiers(cls, text: str) -> list[str]:
        """
        Extracts transaction / invoice / reference IDs.
        Used solely for correlation; does NOT create suspect candidates.
        """
        if not text:
            return []

        matches = cls.TRANSACTION_REGEX.findall(text)
        return list(dict.fromkeys(matches))

    @staticmethod
    def extract_entities(metadata):
        """
        DEMO/TEST ONLY:
        Provides sample entities for offline standalone demonstration.
        This must NEVER be used in production.
        """
        evidence_type = getattr(metadata, "evidence_type", None)

        if evidence_type == "EMAIL":
            return [
                "sender@example.com",
                "receiver@example.com"
            ]
        elif evidence_type == "DATABASE":
            return [
                "Rahul Sharma",
                "123456789"
            ]
        elif evidence_type == "DOCUMENT":
            return [
                "Rahul",
                "Amit"
            ]

        return []

    @classmethod
    def process(cls, evidence, demo_mode: Optional[bool] = None):
        """
        Extracts actor entities from evidence content and updates related_entities.
        Preserves pre-supplied entities if already present.
        Separates transaction identifiers without putting them into related_entities.
        """
        if demo_mode is None:
            demo_mode = DEFAULT_DEMO_MODE

        # Case 1: Evidence already has genuine supplied entities
        if hasattr(evidence, "related_entities") and evidence.related_entities:
            return evidence

        # Case 2: Extract from real evidence content
        content = cls.extract_text_content(evidence)
        actor_pairs = cls.extract_actor_identifiers(content)
        tx_ids = cls.extract_transaction_identifiers(content)

        # Store transaction IDs on evidence for correlation without inflating Suspect Factor
        if tx_ids:
            evidence.related_transactions = tx_ids

        if actor_pairs:
            # Populate related_entities with original display representations
            evidence.related_entities = [orig for _, orig in actor_pairs]
            if hasattr(evidence, "pending_external_inputs"):
                evidence.pending_external_inputs.pop("RELATIONSHIP", None)
            return evidence

        # Case 3: Demo mode fallback for offline testing
        if demo_mode:
            evidence.related_entities = cls.extract_entities(evidence.metadata)
            return evidence

        # Case 4: Production mode with no extractable entities
        evidence.related_entities = []
        if not hasattr(evidence, "pending_external_inputs"):
            evidence.pending_external_inputs = {}

        evidence.pending_external_inputs["RELATIONSHIP"] = (
            "MISSING EXTERNAL INPUT / INTEGRATION PENDING"
        )

        return evidence

    @classmethod
    def generate_suspect_candidates(
        cls,
        evidence_database: list,
        demo_mode: bool = False
    ) -> list[Suspect]:
        """
        Matches same actor identifiers across multiple evidence files,
        deduplicates them with type-aware normalization, and creates Suspect objects.

        Rules:
        - Only actor-like identifiers (email, IPv4, crypto, account) create suspect candidates.
        - Transaction/reference IDs do NOT create suspect candidates.
        - No fictitious human names are invented. The identifier itself is the suspect identity.
        - The same identifier across N evidence files creates exactly ONE candidate linked to all N files.
        - If no identifiers are found, returns an empty list.
        """
        candidate_map: dict[tuple[str, str], dict] = {}

        for evidence in evidence_database:
            entities = getattr(evidence, "related_entities", [])
            for identifier in entities:
                # Classify type to apply proper normalization
                id_type = "UNKNOWN"
                if "@" in identifier:
                    id_type = "EMAIL"
                elif cls.IPV4_REGEX.match(identifier):
                    id_type = "IPV4"
                elif identifier.startswith("0x") and len(identifier) == 42:
                    id_type = "ETHEREUM"
                elif identifier.startswith("bc1") or (
                    len(identifier) >= 26 and identifier[0] in "13"
                ):
                    id_type = "BITCOIN"
                elif identifier.upper().startswith(("ACC", "ACCT", "IBAN")):
                    id_type = "ACCOUNT"
                else:
                    id_type = "ACTOR"

                norm_key = cls.normalize_identifier(identifier, id_type)
                composite_key = (id_type, norm_key)

                if composite_key not in candidate_map:
                    candidate_map[composite_key] = {
                        "display_name": identifier,
                        "evidence_list": [],
                        "evidence_ids": []
                    }

                # Link evidence item without duplicates
                if evidence not in candidate_map[composite_key]["evidence_list"]:
                    candidate_map[composite_key]["evidence_list"].append(evidence)
                    ev_id = getattr(evidence.metadata, "evidence_id", "") or str(id(evidence))
                    candidate_map[composite_key]["evidence_ids"].append(ev_id)

        suspects: list[Suspect] = []
        for (id_type, norm_key), data in candidate_map.items():
            suspect_hash = hashlib.sha256(f"{id_type}:{norm_key}".encode()).hexdigest()[:8].upper()
            suspect_id = f"SUSPECT-{suspect_hash}"
            evidence_count = len(data["evidence_list"])

            # Confidence score indicates recurrence across evidence files (does NOT affect ranking)
            confidence = min(round(evidence_count * 0.25, 2), 1.0)

            suspect = Suspect(
                suspect_id=suspect_id,
                suspect_name=data["display_name"],
                evidence_list=data["evidence_list"],
                linked_evidence_ids=data["evidence_ids"],
                total_epra_score=0.0,
                rank=0,
                confidence_score=confidence
            )
            suspects.append(suspect)

        return suspects