/*
Copyright 2023 The Radius Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

@description('Information about what resource is calling this Recipe. Generated by Radius. For more information visit https://docs.radapp.dev/operations/custom-recipes/')
param context object

@description('Name of the SQL database. Defaults to the name of the Radius SQL resource.')
param database string = context.resource.name

@description('SQL administrator username')
param adminLogin string = 'sa'

@description('SQL administrator password')
@secure()
#disable-next-line secure-parameter-default
param adminPassword string = 'P@ssword1234$$'

@description('Tag to pull for the azure-sql-edge container image.')
param tag string = '1.0.7'

@description('Memory request for the azure-sql-edge deployment.')
param memoryRequest string = '512Mi'

@description('Memory limit for the azure-sql-edge deployment')
param memoryLimit string = '1024Mi'

@description('Initial catalog to connect to. Defaults to empty string (no initial catalog).')
param initialCatalog string = ''

import kubernetes as kubernetes {
  kubeConfig: ''
  namespace: context.runtime.kubernetes.namespace
}

var uniqueName = 'sql-${uniqueString(context.resource.id)}'
var port = 1433
var initialCatalogString = initialCatalog == '' ? '' : 'Initial Catalog=${initialCatalog};'

resource sql 'apps/Deployment@v1' = {
  metadata: {
    name: uniqueName
  }
  spec: {
    selector: {
      matchLabels: {
        app: 'sql'
        resource: context.resource.name
      }
    }
    template: {
      metadata: {
        labels: {
          app: 'sql'
          resource: context.resource.name

          // Label pods with the application name so `rad run` can find the logs.
          'radapp.io/application': context.application == null ? '' : context.application.name
        }
      }
      spec: {
        containers: [
          {
            // This container is the running sql instance.
            name: 'sql'
            image: 'mcr.microsoft.com/azure-sql-edge:${tag}'
            ports: [
              {
                containerPort: port 
              }
            ]
            resources: {
              requests: {
                memory: memoryRequest
              }
              limits: {
                memory: memoryLimit
              }
            }
            env: [
              {
                name: 'ACCEPT_EULA'
                value: '1'
              }
              {
                name: 'MSSQL_SA_PASSWORD'
                value: adminPassword
              }
            ]
          }
        ]
      }
    }
  }
}

resource svc 'core/Service@v1' = {
  metadata: {
    name: uniqueName
    labels: {
      name: uniqueName
    }
  }
  spec: {
    type: 'ClusterIP'
    selector: {
      app: 'sql'
      resource: context.resource.name
    }
    ports: [
      {
        port: port 
      }
    ]
  }
}

output result object = {
  // This workaround is needed because the deployment engine omits Kubernetes resources from its output.
  // This allows Kubernetes resources to be cleaned up when the resource is deleted.
  // Once this gap is addressed, users won't need to do this.
  resources: [
    '/planes/kubernetes/local/namespaces/${svc.metadata.namespace}/providers/core/Service/${svc.metadata.name}'
    '/planes/kubernetes/local/namespaces/${sql.metadata.namespace}/providers/apps/Deployment/${sql.metadata.name}'
  ]
  values: {
    server: '${svc.metadata.name}.${svc.metadata.namespace}.svc.cluster.local'
    port: port
    database: database
    username: adminLogin
  }
  secrets: {
    #disable-next-line outputs-should-not-contain-secrets
    password: adminPassword
    #disable-next-line outputs-should-not-contain-secrets
    connectionString: 'Server=tcp:${svc.metadata.name}.${svc.metadata.namespace}.svc.cluster.local,${port};${initialCatalogString}User Id=${adminLogin};Password=${adminPassword};Encrypt=false'
  }
}
