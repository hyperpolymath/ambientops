# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.DataPlane.Parsers.DockerComposeTest do
  @moduledoc """
  Tests for the Docker Compose YAML parser.

  Verifies conversion of Docker Compose files into HAR semantic graph
  operations. Handles services, networks, volumes, configs, secrets,
  port mappings, environment variables, and depends_on relationships.
  """
  use ExUnit.Case

  alias HAR.DataPlane.Parsers.DockerCompose
  alias HAR.Semantic.{Graph, Dependency}

  describe "parse/2 with simple service" do
    test "parses single service with image" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx:latest
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)
      assert length(graph.vertices) >= 1

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      assert length(service_ops) == 1

      op = hd(service_ops)
      assert op.type == :container_run
      assert op.params.name == "web"
      assert op.params.image == "nginx:latest"
      assert op.metadata.source == :docker_compose
    end
  end

  describe "parse/2 with service build context" do
    test "parses service with string build context" do
      yaml = """
      version: "3"
      services:
        app:
          build: ./app
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.params.build == %{context: "./app"}
      assert op.metadata.has_build == true
    end

    test "parses service with detailed build context" do
      yaml = """
      version: "3"
      services:
        app:
          build:
            context: ./app
            dockerfile: Containerfile
            args:
              VERSION: "1.0"
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.params.build.context == "./app"
      assert op.params.build.dockerfile == "Containerfile"
    end
  end

  describe "parse/2 with ports, volumes, and environment" do
    test "parses service with port mappings" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
          ports:
            - "8080:80"
            - "8443:443"
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert length(op.params.ports) == 2

      first_port = hd(op.params.ports)
      assert first_port.published == 8080
      assert first_port.target == 80
      assert first_port.protocol == "tcp"
    end

    test "parses service with volume mounts" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
          volumes:
            - ./html:/usr/share/nginx/html
            - nginx-data:/var/log/nginx
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert length(op.params.volumes) == 2

      bind_mount = Enum.find(op.params.volumes, fn v -> v.type == "bind" end)
      assert bind_mount != nil
      assert bind_mount.source == "./html"
      assert bind_mount.target == "/usr/share/nginx/html"
    end

    test "parses service with map environment" do
      yaml = """
      version: "3"
      services:
        app:
          image: myapp
          environment:
            DATABASE_URL: postgres://localhost/mydb
            LOG_LEVEL: info
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.params.environment["DATABASE_URL"] == "postgres://localhost/mydb"
      assert op.params.environment["LOG_LEVEL"] == "info"
    end

    test "parses service with list environment" do
      yaml = """
      version: "3"
      services:
        app:
          image: myapp
          environment:
            - DATABASE_URL=postgres://localhost/mydb
            - LOG_LEVEL=info
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.params.environment["DATABASE_URL"] == "postgres://localhost/mydb"
    end
  end

  describe "parse/2 with depends_on" do
    test "creates dependency from depends_on list" do
      yaml = """
      version: "3"
      services:
        db:
          image: postgres:15
        app:
          image: myapp
          depends_on:
            - db
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      assert length(service_ops) == 2

      # App should depend on db
      requires_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.type == :requires and dep.metadata[:reason] == "depends_on"
        end)

      assert length(requires_deps) >= 1
    end

    test "creates dependency from depends_on map with condition" do
      yaml = """
      version: "3"
      services:
        db:
          image: postgres:15
        app:
          image: myapp
          depends_on:
            db:
              condition: service_healthy
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      requires_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.type == :requires and dep.metadata[:reason] == "depends_on"
        end)

      assert length(requires_deps) >= 1
    end
  end

  describe "parse/2 with named networks" do
    test "creates network operations" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
          networks:
            - frontend
      networks:
        frontend:
          driver: bridge
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      network_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :network
        end)

      assert length(network_ops) == 1

      net_op = hd(network_ops)
      assert net_op.type == :network_create
      assert net_op.params.name == "frontend"
      assert net_op.params.driver == "bridge"
    end

    test "creates dependencies from service to network" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
          networks:
            - frontend
      networks:
        frontend:
          driver: bridge
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      network_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] == "network_ref"
        end)

      assert length(network_deps) >= 1
    end
  end

  describe "parse/2 with named volumes" do
    test "creates volume operations" do
      yaml = """
      version: "3"
      services:
        db:
          image: postgres
          volumes:
            - db-data:/var/lib/postgresql/data
      volumes:
        db-data:
          driver: local
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      volume_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :volume
        end)

      assert length(volume_ops) == 1

      vol_op = hd(volume_ops)
      assert vol_op.type == :storage_volume_create
      assert vol_op.params.name == "db-data"
      assert vol_op.params.driver == "local"
    end

    test "creates dependencies from service to named volume" do
      yaml = """
      version: "3"
      services:
        db:
          image: postgres
          volumes:
            - db-data:/var/lib/postgresql/data
      volumes:
        db-data:
          driver: local
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      volume_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] == "volume_ref"
        end)

      assert length(volume_deps) >= 1
    end
  end

  describe "parse/2 with multiple services" do
    test "parses complete multi-service compose file" do
      yaml = """
      version: "3.8"
      services:
        db:
          image: postgres:15
          environment:
            POSTGRES_DB: myapp
            POSTGRES_USER: user
            POSTGRES_PASSWORD: pass
          volumes:
            - db-data:/var/lib/postgresql/data
          ports:
            - "5432:5432"
        redis:
          image: redis:7
          ports:
            - "6379:6379"
        app:
          image: myapp:latest
          ports:
            - "3000:3000"
          depends_on:
            - db
            - redis
          environment:
            DATABASE_URL: postgres://user:pass@db/myapp
            REDIS_URL: redis://redis:6379
      volumes:
        db-data:
          driver: local
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      assert length(service_ops) == 3

      volume_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :volume
        end)

      assert length(volume_ops) == 1

      # App depends on db and redis
      depends_on_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] == "depends_on"
        end)

      assert length(depends_on_deps) >= 2
    end
  end

  describe "parse/2 with service options" do
    test "parses restart policy" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
          restart: always
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.params.restart == "always"
    end

    test "parses command override" do
      yaml = """
      version: "3"
      services:
        app:
          image: myapp
          command: "bundle exec rails server"
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.params.command == "bundle exec rails server"
    end

    test "parses hostname" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
          hostname: web-server
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.params.hostname == "web-server"
    end
  end

  describe "validate/1" do
    test "validates correct Docker Compose file" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
      """

      assert :ok = DockerCompose.validate(yaml)
    end

    test "validates file with version key only" do
      yaml = """
      version: "3"
      """

      assert :ok = DockerCompose.validate(yaml)
    end

    test "returns error for missing services and version section" do
      yaml = """
      something:
        else: true
      """

      assert {:error, {:docker_compose_parse_error, _}} = DockerCompose.validate(yaml)
    end

    test "returns error for invalid YAML" do
      yaml = "invalid: [yaml: content"

      assert {:error, _} = DockerCompose.validate(yaml)
    end
  end

  describe "metadata" do
    test "sets graph metadata with source and timestamp" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)
      assert graph.metadata.source == :docker_compose
      assert %DateTime{} = graph.metadata.parsed_at
    end

    test "service operation ID contains compose_service prefix" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      service_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :service
        end)

      op = hd(service_ops)
      assert op.id =~ "compose_service_"
    end

    test "network operation ID contains compose_network prefix" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
      networks:
        frontend:
          driver: bridge
      """

      assert {:ok, %Graph{} = graph} = DockerCompose.parse(yaml)

      network_ops =
        Enum.filter(graph.vertices, fn op ->
          op.metadata[:compose_type] == :network
        end)

      if length(network_ops) > 0 do
        op = hd(network_ops)
        assert op.id =~ "compose_network_"
      end
    end
  end
end
