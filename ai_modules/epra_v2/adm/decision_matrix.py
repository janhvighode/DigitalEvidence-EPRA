"""
decision_matrix.py

Stores all finalized Adaptive Decision Matrices (ADM)
for different evidence types.

NOTE:
This file only stores data.
No business logic should be written here.
"""

ADM_TABLE = {

    "IMAGE": {
        "AR": 0.15,
        "CI": 0.20,
        "BI": 0.10,
        "SI": 0.30,
        "II": 0.25
    },

    "VIDEO": {
        "AR": 0.15,
        "CI": 0.20,
        "BI": 0.10,
        "SI": 0.25,
        "II": 0.30
    },

    "AUDIO": {
        "AR": 0.15,
        "CI": 0.20,
        "BI": 0.15,
        "SI": 0.15,
        "II": 0.35
    },

    "EMAIL": {
        "AR": 0.15,
        "CI": 0.20,
        "BI": 0.30,
        "SI": 0.10,
        "II": 0.25
    },

    "PDF": {
        "AR": 0.15,
        "CI": 0.30,
        "BI": 0.10,
        "SI": 0.10,
        "II": 0.35
    },

    "DOCUMENT": {
        "AR": 0.15,
        "CI": 0.30,
        "BI": 0.15,
        "SI": 0.10,
        "II": 0.30
    },

    "SPREADSHEET": {
        "AR": 0.15,
        "CI": 0.30,
        "BI": 0.10,
        "SI": 0.05,
        "II": 0.40
    },

    "EXECUTABLE": {
        "AR": 0.35,
        "CI": 0.20,
        "BI": 0.15,
        "SI": 0.05,
        "II": 0.25
    },

    "DATABASE": {
        "AR": 0.20,
        "CI": 0.25,
        "BI": 0.15,
        "SI": 0.10,
        "II": 0.30
    },

    "LOG": {
        "AR": 0.20,
        "CI": 0.20,
        "BI": 0.35,
        "SI": 0.05,
        "II": 0.20
    },

    "ARCHIVE": {
        "AR": 0.30,
        "CI": 0.20,
        "BI": 0.10,
        "SI": 0.10,
        "II": 0.30
    },

    "UNKNOWN": {
        "AR": 0.20,
        "CI": 0.20,
        "BI": 0.20,
        "SI": 0.20,
        "II": 0.20
    }

}