#!/bin/bash

set -eu

if [[ -n "$NO_PROXY" ]]; then
  echo "$OM_IP $OPSMAN_DOMAIN_OR_IP_ADDRESS" >> /etc/hosts
fi

cwd="${PWD}"
stemcell_versions_dir="${cwd}/stemcell-versions"

STEMCELL_VERSION=$(
  cat ./pivnet-product/metadata.json |
  jq --raw-output \
    '
    [
      .Dependencies[]
      | select(.Release.Product.Name | contains("Stemcells"))
      | .Release.Version
    ]
    | map(split(".") | map(tonumber))
    | transpose | transpose
    | max // empty
    | map(tostring)
    | join(".")
    '
)

if [ -n "$STEMCELL_VERSION" ]; then
  diagnostic_report=$(
    om-linux \
      --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
      --username $OPS_MGR_USR \
      --password $OPS_MGR_PWD \
      --skip-ssl-validation \
      curl --silent --path "/api/v0/diagnostic_report"
  )

  stemcell=$(
    echo $diagnostic_report |
    jq \
      --arg version "$STEMCELL_VERSION" \
      --arg glob "$IAAS" \
    '.stemcells[] | select(contains($version) and contains($glob))'
  )

  if [[ -z "$stemcell" ]]; then
    echo "Requires stemcell $STEMCELL_VERSION"

    product_slug=$(
      jq --raw-output \
        '
        if any(.Dependencies[]; select(.Release.Product.Name | contains("Stemcells for PCF (Windows)"))) then
          "stemcells-windows-server"
        else
          "stemcells"
        end
        ' < pivnet-product/metadata.json
    )

    echo $STEMCELL_VERSION >> "${stemcell_versions_dir}/${product_slug}"
  fi
fi

# Should the slug contain more than one product, pick only the first.
FILE_PATH=`find ./pivnet-product -name *.pivotal | sort | head -1`
om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPS_MGR_USR -p $OPS_MGR_PWD -k --request-timeout 3600 upload-product -p $FILE_PATH
