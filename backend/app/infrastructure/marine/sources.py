"""Attribution and redistribution metadata for datasets actually in the pipeline."""

SOURCES = [
    {
        "id": "ign",
        "families": ["port-infrastructure"],
        "dataset": "BD TOPO construction_lineaire (nature=Quai)",
        "attribution": "© IGN, BD TOPO, édition WFS 2026-06-15 (modified by NoWave)",
        "url": "https://www.data.gouv.fr/datasets/bd-topo-r",
        "license": "Licence Ouverte 2.0",
        "license_url": "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
    },
    {
        "id": "shom",
        "families": ["seamarks"],
        "dataset": "Balisage maritime",
        "attribution": "Shom, https://dx.doi.org/10.17183/DOI_BALISAGE_MARITIME",
        "url": "https://diffusion.shom.fr/donnees/balisage_maritime.html",
        "license": "Licence Ouverte 2.0",
        "license_url": "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
    },
    {
        "id": "noaa",
        "families": ["seamarks", "port-infrastructure"],
        "dataset": "NOAA ENC Direct to GIS",
        "attribution": "NOAA Office of Coast Survey; ENC Direct to GIS (modified by NoWave)",
        "url": "https://nauticalcharts.noaa.gov/data/gis-data-and-services.html",
        "license": "CC0 1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
    },
    {
        "id": "openwaters",
        "families": ["seamarks"],
        "dataset": "Open Waters Seamap",
        "attribution": "© Open Waters: Seamap; © OpenStreetMap contributors (modified by NoWave)",
        "url": "https://openwaters.io/charts/seamap",
        "license": "CC BY 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
    },
    {
        "id": "osm",
        "families": ["seamarks", "port-infrastructure"],
        "dataset": "OpenStreetMap / Shortbread",
        "attribution": "© OpenStreetMap contributors (modified by NoWave)",
        "url": "https://www.openstreetmap.org/copyright",
        "license": "ODbL 1.0",
        "license_url": "https://opendatacommons.org/licenses/odbl/1-0/",
    },
]
