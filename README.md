# HCL Sametime TechNotes

Community-maintained technical notes, configuration guides, troubleshooting information, and administrative tools for HCL Sametime.

> **Disclaimer**
>
> This is a community project and is not an official HCL Software repository.
> The documentation and tools are provided without warranty. Always test changes in a non-production environment first.

## TechNotes

### HCL Sametime 12.0.4

#### Authentication

- [SAML Integration with Keycloak under Docker](12.0.4/authentication/saml-keycloak/)
  - SAML configuration guide
  - `check-saml.sh` configuration validation tool

- [OIDC Integration with Keycloak under Docker](12.0.4/authentication/oidc-keycloak/)
  - OpenID Connect configuration guide
  - Keycloak OIDC configuration
  - `check-oidc.sh` configuration validation tool

## Repository structure

Each TechNote is stored together with its related scripts, examples, and other resources.

```text
12.0.4/
└── authentication/
    └── saml-keycloak/
        ├── README.md
        └── check-saml.sh
```

## Contributions

Corrections, improvements, and additional technical notes are welcome.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
