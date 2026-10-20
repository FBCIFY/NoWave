import asyncio
from dataclasses import replace

import mapbox_vector_tile
import pytest
from shapely.geometry import Point, box

from app.application.services.marine_tiles import MarineTileService
from app.domain.marine import HarbourFeature, MarineFamily, ProviderUnavailable
from app.domain.marine_tile import Tile
from app.infrastructure.marine.harbours import HarbourProvider, merge_harbours


def vector():
    features = [
        (1, Point(2048, 2048), 'harbour', 'marina', 'Port réel'),
        (1, box(0, 0, 4000, 4000), 'harbour', 'marina', 'Port réel'),
        (2, Point(2100, 2100), 'shoreline_construction', 'pier', 'Quai nommé'),
        (3, Point(3000, 2000), 'harbour', 'unknown', 'Port générique'),
    ]
    return mapbox_vector_tile.encode({'name': 'seamark', 'features': [
        {'id': i, 'geometry': g, 'properties': {'osm_id': i, 'type': t, 'category': c, 'name': n}}
        for i, g, t, c, n in features
    ]})


class HTTP:
    def __init__(self):
        self.calls = []
        self.fail = False

    async def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        if self.fail:
            raise ProviderUnavailable('offline')
        return vector()


@pytest.mark.parametrize('zoom,requests', [(5, 0), (6, 16), (7, 4), (8, 1), (14, 1)])
def test_real_point_contract_low_zoom_requests_mvt_and_cache(zoom, requests):
    async def run():
        http = HTTP()
        service = MarineTileService([HarbourProvider(http)])
        tile = Tile(zoom, 1 << (zoom - 1), 1 << (zoom - 1))
        result = await service.get_tile(tile, MarineFamily.HARBOURS)
        features = mapbox_vector_tile.decode(result.content)['harbour']['features']
        assert len(http.calls) == requests
        assert len(features) == (2 if requests else 0)
        if requests:
            assert {f['properties']['category'] for f in features} == {'marina', 'harbour'}
            assert all(f['geometry']['type'] == 'Point' for f in features)
            assert all(f['properties']['position_method'] == 'provider-point' for f in features)
            assert 'Quai nommé' not in str(features)
            assert all(c[1]['ttl'] == 86400 and c[1]['vector_tile'] for c in http.calls)
            assert (await service.get_tile(tile, MarineFamily.HARBOURS)).content == result.content
            assert len(http.calls) == requests
    asyncio.run(run())


def test_outage_is_not_cached_as_empty_and_recovers():
    async def run():
        http = HTTP()
        service = MarineTileService([HarbourProvider(http)])
        http.fail = True
        with pytest.raises(ProviderUnavailable):
            await service.get_tile(Tile(6, 33, 23), MarineFamily.HARBOURS)
        assert not service._cache
        http.fail = False
        assert (await service.get_tile(Tile(6, 33, 23), MarineFamily.HARBOURS)).content
    asyncio.run(run())


def test_identity_dedup_keeps_provenance_not_nearby_distinct_ports():
    first = HarbourFeature(id='one', source='a', source_id='1', source_priority=10,
                           geometry=Point(6, 43), external_ids=('qualified:1',),
                           provenance=('a:1',), name='Port')
    second = replace(first, id='two', source='b', provenance=('b:2',))
    neighbour = replace(first, id='three', external_ids=('qualified:3',))
    result = merge_harbours([neighbour, second, first])
    assert len(result.features) == 2
    assert result.features[0].provenance == ('a:1', 'b:2')
    with pytest.raises(ValueError):
        replace(first, geometry=box(5, 42, 6, 43))


def test_one_missing_child_rejects_partial_z6_coverage():
    class PartialHTTP(HTTP):
        async def get(self, url, **kwargs):
            if url.endswith('/132/92.pbf'):
                raise ProviderUnavailable('one missing child')
            return await super().get(url, **kwargs)

    async def run():
        provider = HarbourProvider(PartialHTTP())
        with pytest.raises(ProviderUnavailable, match='Incomplete'):
            await provider.fetch(Tile(6, 33, 23), MarineFamily.HARBOURS)
    asyncio.run(run())


def test_provider_mvt_identity_prevents_node_way_numeric_osm_id_collision():
    class DistinctHTTP(HTTP):
        async def get(self, url, **kwargs):
            return mapbox_vector_tile.encode({'name': 'seamark', 'features': [
                {'id': mvt_id, 'geometry': Point(2000, 2000),
                 'properties': {'type': 'harbour', 'osm_id': 42, 'name': 'Port'}}
                for mvt_id in (84, 85)
            ]})

    async def run():
        result = await HarbourProvider(DistinctHTTP()).fetch(Tile(8, 132, 93), MarineFamily.HARBOURS)
        assert len(result.features) == 2
        assert len({f.id for f in result.features}) == 2
        assert all(f.source_id == '42' for f in result.features)
    asyncio.run(run())
