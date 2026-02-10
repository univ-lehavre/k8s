import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'fr-FR',
  title: 'ATLAS Platform',
  description: 'Infrastructure Kubernetes pour la recherche et la collaboration',
  base: '/k8s/',

  ignoreDeadLinks: [
    /\.\.\//, // Links to repo root files (../.ansible-lint, ../.yamllint)
  ],

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/k8s/favicon.svg' }],
  ],

  themeConfig: {
    nav: [
      { text: 'Accueil', link: '/' },
      { text: 'Deploiement', link: '/deployment-priority' },
      { text: 'Securite', link: '/authentication' },
      { text: 'Contribuer', link: '/CONTRIBUTING' },
    ],

    sidebar: [
      {
        text: 'Deploiement',
        items: [
          { text: 'Guide de deploiement', link: '/deployment-priority' },
        ],
      },
      {
        text: 'Securite',
        items: [
          { text: 'Authentification', link: '/authentication' },
          { text: 'Autorisations', link: '/authorization' },
          { text: 'Secrets et chiffrement', link: '/secrets-encryption' },
          { text: 'Flux reseau', link: '/network-flows' },
        ],
      },
      {
        text: 'Projet',
        items: [
          { text: 'Contribuer', link: '/CONTRIBUTING' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/univ-lehavre/k8s' },
    ],

    editLink: {
      pattern: 'https://github.com/univ-lehavre/k8s/edit/main/docs/:path',
      text: 'Modifier cette page sur GitHub',
    },

    search: {
      provider: 'local',
      options: {
        translations: {
          button: { buttonText: 'Rechercher', buttonAriaLabel: 'Rechercher' },
          modal: {
            noResultsText: 'Aucun resultat pour',
            resetButtonTitle: 'Effacer la recherche',
            footer: {
              selectText: 'selectionner',
              navigateText: 'naviguer',
              closeText: 'fermer',
            },
          },
        },
      },
    },

    outline: { label: 'Sur cette page' },

    docFooter: {
      prev: 'Page precedente',
      next: 'Page suivante',
    },

    footer: {
      message: 'Publie sous licence MIT',
      copyright: 'ATLAS Platform',
    },
  },
})
