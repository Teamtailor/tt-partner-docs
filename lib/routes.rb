Router.draw do
  route :partners
  route :job_boards do
    route :direct_apply
  end
end