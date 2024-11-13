# Unbound DNS Server Docker Image

![Unbound](./img/unbound.svg "Unbound")

## What is this?

This is a fork of [Matthew Vance's ever-popular Unbound Docker image](https://github.com/MatthewVance/unbound-docker), prioritizing maintainability, speed of updates, ease of initial use, and final image size. Unbound in this image is also compiled with as many additional modules as possible, such as cachedb for additional caching to Redis.

## What is Unbound?

Unbound is a validating, recursive, and caching DNS resolver.
Instead of contacting an external resolver like your ISP, Google, or Cloudflare, you're your own resolver. This can mean:

* Overall faster response times (once your cache is built)
* 100% control over your DNS responses. For example, some resolvers like to hijack NXDOMAIN responses to return their own error or search page. Yes, I'm looking at you, AT&T.
* Overall privacy improvements. As another example, resolvers can mine your DNS data to sell off to third parties. Yes, I'm STILL looking at you, AT&T.

For more information, take a look at the official site at [https://unbound.net/](https://unbound.net/)

## Dude, there's, like, A LOT of Unbound Docker images already. Why another one?

![But why?](./img/but-why.gif "But why?")

I had a few goals in mind when building this image:

* I plan on eventually converting all of my currently in-use Docker images in my home into my own spin-off images. This will allow me to update packages at my own pace (usually ASAP), as well as ensuring everything is built to my own preferences.
* This actually started as a learning project to see how an image is built from start to finish, using somewhat up-to-date Docker syntax tooling.
* Bringing those two together, I planned this out so that version updates for Unbound and dependencies are as painless as possible.

## This is distroless, right? It's gotta be distroless! That's the thing now!

While it's not *technically* distroless, it's 99% of the way there, and probably where it'll stay. There is a [bootstrap script](./data/unbound.bootstrap) that runs on initial boot that configures performance parameters, enables unbound-control (if set), creates the root anchor, and then finally deletes BusyBox, any symlinks to it, and itself. This is intended to be an image that "just works" with sensible defaults, and the bootstrap is a core part of that.

In my opinion, it's **Good Enough**™

## Image tags and versioning

Tags and versions are commit-based at the lowest level, with each Unbound version having its own branch for dependency management.

* `latest`
  * The most up-to-date image available. This is the default if no tag is specified.
    * ```GibsonSoft/unbound```
    * ```GibsonSoft/unbound:latest```
* `<Unbound version>` or `<Unbound version>-latest`
  * The latest image available for the specified Unbound version.
    * ```GibsonSoft/unbound:1.23.0```
    * ```GibsonSoft/unbound:1.23.0-latest```
* `<Unbound version>-<Short commit hash>`
  * Pulls the image for a specific commit made. Use this if you absolutely need to pin to a specific set of dependencies for some reason. Generally not recommended unless you're troubleshooting an issue.
    * ```GibsonSoft/unbound:1.23.0-jd84hf8```

## How to use this image

### Assumptions

The examples below assume that you have a general understanding of the Linux CLI and networking knowledge. You will most likely need to do some network configuration, such as opening ports on your firewall and/or port forwarding, to fully use Unbound on your entire network.

Please refer to your specific distro's documentation for more information.

##

### Docker Compose

I highly recommend using Docker Compose for setting up the container versus running Docker commands directly, and will be using it for the examples going forward. Even if you're not mixing multiple images, it makes it much easier to manage your running containers and keep track of your settings and config files.

If you have Docker Desktop installed, you should already have Compose available and can skip to following the examples. Otherwise you'll need to install the plugin first before continuing. It should only take a few minutes, I promise!

#### Docker Compose Resources

* [Installing Docker Compose using the Docker repository](https://docs.docker.com/compose/install/linux/#install-using-the-repository)
* [Docker Compose overview](https://docs.docker.com/compose/)
* [Compose file reference](https://docs.docker.com/reference/compose-file/)
* [docker compose subcommands](https://docs.docker.com/reference/cli/docker/compose/)

##

### Basic usage

A very basic `docker-compose.yml` can look something like:

```yaml
services:
  unbound:
    image: gibsonsoft/unbound:latest
    container_name: unbound
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
```

This configuration will:

* Use the ```gibsonsoft/unbound:latest``` image
* Create a Docker container named ```unbound```
* Sets the container to always restart unless specifically stopped by you
* Map local port 53 to container port 53 for both TCP and UDP connections
  * If you wish to map a different local port, change the first number. E.g. for local port 5335, use ```"5335:53/tcp"``` and ```"5335:53/udp"``` instead.

Create the above file and place it in a folder somewhere where it will live. Navigate to the folder, then run ```docker compose up -d``` to start the container.

Run ```docker compose ps``` to check the status of your running container, and you should see something like the following:

```console
unbound   gibsonsoft/unbound:latest   "/unbound -d -c /etc…"   unbound   22 minutes ago   Up 14 seconds (healthy)   0.0.0.0:53->53/tcp, 0.0.0.0:53->53/udp
```

If it's showing (healthy) in the status, then congratulations, you're now running your own DNS resolver!

##

### Tuning performance

By default, this image tunes performance parameters based on all resources available to the container. Most of the time you'll only need a small subset of resources allocated to it instead. You can use the Compose elements `cpuset` and `mem_limit` to fine-tune these.

For example, to limit Unbound to using 1GB RAM and CPU cores 0 to 3 (4 cores total):

```yaml
services:
  unbound:
    image: gibsonsoft/unbound:latest
    container_name: unbound
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    cpuset: 0-3
    mem_limit: 1gb
```

This should be plenty for most installations, but you can tune these further as you see fit.

Once those are added, make sure to run ```docker compose down && docker compose up -d``` so that the changes take effect and parameters are retuned.

For more information on these elements, see the Compose file references for [```cpuset```](https://docs.docker.com/reference/compose-file/services/#cpuset) and [```mem_limit```](https://docs.docker.com/reference/compose-file/services/#mem_limit).

##

### Enable unbound-control

By default, unbound-control is disabled for security reasons since it can allow remote access to your Unbound instance if your server is misconfigured. However, you'll probably want to enable it once everything is set up so that you can view statistics such as cache hits/misses.

To enable, add the environment variable ```CONTROL_ENABLE``` to your docker-compose.yml, and set it to ```true```:

```yaml
services:
  unbound:
    image: gibsonsoft/unbound:latest
    container_name: unbound
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    cpuset: 0-3
    mem_limit: 1gb
    environment:
      CONTROL_ENABLE: true
```

Run ```docker compose down && docker compose up -d``` to apply the change. ```unbound-control``` should now be enabled and can be tested with ```docker exec -it unbound unbound-control stats_noreset```. You should see something like the following:

```console
thread0.num.queries=2
thread0.num.queries_ip_ratelimited=0
thread0.num.queries_cookie_valid=0
thread0.num.queries_cookie_client=0
thread0.num.queries_cookie_invalid=0
thread0.num.cachehits=0
...
more stats
...
```

**Be sure to run ```unbound-control stats_noreset``` and NOT ```unbound-control stats```!** ```stats``` will reset your statistics after it's run, which is probably NOT what you want.

For more information, check out the [unbound-control documentation.](https://www.nlnetlabs.nl/documentation/unbound/unbound-control/)

##

### Mount configuration directory

For maximum control, you can mount the ```/etc/unbound``` directory to a local folder to edit the *.conf files directly. This will be required for more advanced features, such as enabling cachedb for Redis caching.

To do this, we can create a named Docker volume in our ```docker-compose.yml```:

```yaml
services:
  unbound:
    image: gibsonsoft/unbound:latest
    container_name: unbound
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    cpuset: 0-3
    mem_limit: 1gb
    environment:
      CONTROL_ENABLE: true
    volumes:
      - unbound_config:/etc/unbound
volumes:
  unbound_config:
    name: unbound_config
    driver: local
    driver_opts:
      type: none
      device: ./etc/unbound
      o: bind
```

After the usual ```docker compose down && docker compose up -d```, you should now see the ```./etc/unbound``` directory in your working compose directory. The configuration for this image is split up into multiple ```*.conf``` files in the ```conf.d``` subfolder for maintainability. There are also respective ```*.conf.default``` files that contain the default configuration from when the container was created. The ```unbound.conf.example``` file contains all of the possible settings for your respective version of Unbound.

Do note that this is a two-way bind; if you delete the folder on your host machine, your container will no longer work. You'll need to manually delete the volume with ```docker volume rm unbound_config``` and recreate the container.

For more information on configuration settings, see [the official unbound.conf documentation.](https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html)

## Notes

### Logging

Logging is very limited in the default config, and set to ```Verbosity: 0```. If you wish to increase the verbosity, you'll first need to mount the configuration directory (as explained above), and then edit ```/etc/unbound/conf.d/logging.conf``` to set verbosity to your desired value. Verbosity ranges from 0 to 5, with higher verbosity logging more information. Verbosity values are explained in the [unbound.conf documentation about server options.](https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#server-options)

##

### Healthcheck

By default, this image includes a healthcheck that performs a query for *cloudflare.com* on localhost at a regular interval. This can be configured or disabled inside of your ```docker-compose.yml``` if you wish to use something different.

For reference, the default healthcheck for this image would look something like this inside of your ```docker-compose.yml```:

```yaml
services:
  unbound:
    healthcheck:
      test: ["/bin/drill", "@127.0.0.1", "cloudflare.com"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 10s
      start_interval: 5s
```

Information on healthcheck settings can be found in [the Docker Compose file reference.](https://docs.docker.com/reference/compose-file/services/#healthcheck)

##

### Known issues

The following message may appears in the logs about IPv6 Address Assignment:

`[1644625926] libunbound[24:0] error: udp connect failed: Cannot assign requested address for 2001:xxx:xx::x port 53`

While annoying, the container works despite the error. Search this issues in this repo for "udp connect" to see more discussion.

## User feedback

### Issues and Contributing

I'm always open to receiving updates, improvements, etc!

I'm not looking for anything specific in PRs, but I do ask to follow a "common sense" approach. This can include, but not limited to:

* Being familiar with the code base and documentation.
* Understanding what your new or edited code can affect.
* Document what has been changed, added, etc. in the PR.

Basically, it comes down to "do you understand what this widget does?" If the answer is "no", then you probably shouldn't touch it without opening an issue and asking first.

Additionally, I absolutely will not tolerate any negative behavior. Bullying, aggression, belittling and just overall shitty behavior is a no-go, and will get you a swift boot from this repo.
We're all in this together, and we all want the same thing: making OSS better through teamwork.

["Be excellent to each other!"](https://www.youtube.com/watch?v=rph_1DODXDU)

## Built Dependencies

This image builds the following dependencies from source:

* Hiredis: https://github.com/redis/hiredis
* LDNS: https://github.com/NLnetLabs/ldns
* OpenSSL: https://github.com/openssl/openssl
* Protobuf: https://github.com/protocolbuffers/protobuf
* Protobuf-C: https://github.com/protobuf-c/protobuf-c
* Unbound: https://github.com/NLnetLabs/unbound

## License

Unless otherwise specified, all code is released under the MIT License (MIT).
See the [repository's `LICENSE`
file](LICENSE) for
details.
