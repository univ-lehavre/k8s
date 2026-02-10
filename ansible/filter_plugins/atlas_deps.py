"""Filtre Ansible pour la résolution de dépendances ATLAS.

Utilisé par playbooks/deploy.yml pour résoudre l'arbre de dépendances
d'un composant cible et renvoyer l'ordre de déploiement (tri topologique).
"""

from collections import deque


class FilterModule:
    """Filtres Jinja2 pour la résolution de dépendances."""

    def filters(self):
        return {
            "resolve_deps": self.resolve_deps,
        }

    @staticmethod
    def resolve_deps(graph, target):
        """Résout les dépendances de *target* et renvoie l'ordre de déploiement.

        Args:
            graph: dict atlas_components (clé = nom composant, valeur = définition)
            target: nom du composant cible

        Returns:
            list[str]: composants dans l'ordre topologique (dépendances d'abord)

        Raises:
            ValueError: composant inconnu ou dépendance circulaire
        """
        if target not in graph:
            available = ", ".join(sorted(graph.keys()))
            raise ValueError(
                f"Composant inconnu : {target}. "
                f"Disponibles : {available}"
            )

        # BFS pour collecter tous les ancêtres
        needed = set()
        queue = deque([target])
        while queue:
            node = queue.popleft()
            if node in needed:
                continue
            needed.add(node)
            for dep in graph[node].get("deps", []):
                if dep not in graph:
                    raise ValueError(
                        f"Dépendance inconnue : {dep} (requis par {node})"
                    )
                queue.append(dep)

        # Tri topologique (Kahn) sur le sous-graphe
        in_degree = {n: 0 for n in needed}
        for n in needed:
            for dep in graph[n].get("deps", []):
                if dep in needed:
                    in_degree[n] += 1

        queue = deque(sorted(n for n in needed if in_degree[n] == 0))
        ordered = []
        while queue:
            node = queue.popleft()
            ordered.append(node)
            for n in sorted(needed):
                if node in graph[n].get("deps", []):
                    in_degree[n] -= 1
                    if in_degree[n] == 0:
                        queue.append(n)

        if len(ordered) != len(needed):
            raise ValueError("Dépendance circulaire détectée")

        return ordered
