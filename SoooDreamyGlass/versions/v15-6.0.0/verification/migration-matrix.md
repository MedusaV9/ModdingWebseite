# 6.0 server migration matrix

| Case | Expected result |
|---|---|
| Authenticated export | schema 1 bundle, source version/member, logical SHA-256 digest |
| Strong file passphrase | AES-GCM envelope using PBKDF2-HMAC-SHA256, 210,000 iterations |
| Fresh single-member destination | logical couple import succeeds |
| Destination with activity | `409 migration_destination_not_empty`, no mutation |
| Changed bundle content | `400 migration_digest_mismatch`, no mutation |
| Unknown future schema | `409 unsupported_migration`, no mutation |
| Source tokens against destination | `401 invalid_token` |
| Existing destination token | remapped to imported source member and remains valid |
| Partner re-pair | new code creates a new destination token for the original partner identity |
| Re-export after import/re-pair | normalized logical couple JSON equals server A export |
| Binary media | explicitly excluded; admin copies media directory separately |

The automated fixture exercises messages, bucket items, events, profiles, pairing, tampering, schema rejection, and non-empty rejection across two independently running server instances.
