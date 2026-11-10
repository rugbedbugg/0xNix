#!/bin/sh
# PLUGIN_NAME=nixospam
# PLUGIN_VERSION=1.0.0

PREQS_MET=NO
if [ -e "${ROOTDIR}etc/NIXOS" ] && [ -d "${ROOTDIR}etc/pam.d" ]; then
    PREQS_MET=YES
fi
Register --test-no CUST-9268 --preqs-met "$PREQS_MET" --weight L --network NO \
    --category security --description "Check PAM modules referenced by NixOS" --progress
if [ "$SKIPTEST" -eq 0 ]; then
    # Reading the service files follows their NixOS symlinks without searching
    # inactive packages in the store. PAM controls in brackets can span fields.
    if NIXOS_PAM_MODULES=$(
        for NIXOS_PAM_SERVICE in "${ROOTDIR}etc/pam.d/"*; do
            case "$NIXOS_PAM_SERVICE" in *.pam-old) continue ;; esac
            [ -f "$NIXOS_PAM_SERVICE" ] || continue
            # shellcheck disable=SC2016
            "$AWKBINARY" '
                $1 ~ /^-?(auth|account|password|session)$/ {
                    for (field = 2; field <= NF; field++) {
                        if ($field ~ /^#/) break
                        if ($field ~ /^\/nix\/store\/[^[:space:]]+\/pam_[^/[:space:]]+\.so$/) {
                            print $field
                            break
                        }
                    }
                }
            ' "$NIXOS_PAM_SERVICE" || exit 1
        done
    ); then
        NIXOS_PAM_MODULES=$(printf '%s\n' "$NIXOS_PAM_MODULES" | "$SORTBINARY" -u)
        NIXOS_PAM_COUNT=0
        NIXOS_PAM_MISSING=0
        for NIXOS_PAM_MODULE in $NIXOS_PAM_MODULES; do
            if [ -f "${ROOTDIR%/}${NIXOS_PAM_MODULE}" ]; then
                NIXOS_PAM_COUNT=$((NIXOS_PAM_COUNT + 1))
                LogText "Result: found referenced PAM module ${NIXOS_PAM_MODULE}"
                Report "pam_module[]=${NIXOS_PAM_MODULE}"
            else
                NIXOS_PAM_MISSING=1
                ReportWarning "$TEST_NO" "A referenced NixOS PAM module is missing" "$NIXOS_PAM_MODULE"
            fi
        done
        if [ "$NIXOS_PAM_MISSING" -eq 0 ] && [ "$NIXOS_PAM_COUNT" -gt 0 ]; then
            LogText "Result: found ${NIXOS_PAM_COUNT} distinct PAM modules referenced by NixOS"
            Display --indent 2 --text "- PAM modules referenced by NixOS" --result "$STATUS_FOUND" --color GREEN
        else
            if [ "$NIXOS_PAM_COUNT" -eq 0 ] && [ "$NIXOS_PAM_MISSING" -eq 0 ]; then
                ReportWarning "$TEST_NO" "No Nix store PAM module references were found"
            fi
            Display --indent 2 --text "- PAM modules referenced by NixOS" --result "$STATUS_WARNING" --color RED
        fi
    else
        ReportWarning "$TEST_NO" "Could not read the NixOS PAM service files"
        Display --indent 2 --text "- PAM modules referenced by NixOS" --result "$STATUS_WARNING" --color RED
    fi
fi
