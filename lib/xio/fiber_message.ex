defmodule ZIO.FiberMessage do
  @type t ::
          :start
          | {:add_observer, (ZIO.Exit.t() -> any())}
          | :interrupt
          | {:resume, ZIO.zio()}
end
