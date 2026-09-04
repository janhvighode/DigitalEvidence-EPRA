from models.custody_log import CustodyLog


class CustodyService:

    @staticmethod
    def create_log(
        db,
        evidence_id,
        investigator_name,
        action,
        remarks=None
    ):

        log = CustodyLog(
            evidence_id=evidence_id,
            investigator_name=investigator_name,
            action=action,
            remarks=remarks
        )

        db.add(log)
        db.commit()
        db.refresh(log)

        return log