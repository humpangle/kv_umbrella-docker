import Config

config :libcluster,
  debug: System.get_env("DEBUG_LIB_CLUSTER") == "true"
