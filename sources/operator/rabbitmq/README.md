# rabbitmq — source operator (témoin OP5 du moteur operator)

Manifestes de la release officielle RabbitMQ cluster-operator
(https://github.com/rabbitmq/cluster-operator/releases — cluster-operator.yml),
vendorisés tels quels : 16 documents dont 1 CRD (`rabbitmqclusters.rabbitmq.com`).

Consommés par un PromiseRequest `type: operator` (source = CE repo à un TAG pinné,
`path: sources/operator/rabbitmq`) : la CRD devient l'API de la promesse (spec+status),
les manifestes ENTIERS deviennent ses dependencies (opérateur installé 1×/Destination).
