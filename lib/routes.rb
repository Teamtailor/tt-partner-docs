Router.draw do
  route :partners
  route :job_boards do
    route :direct_apply
  end
  route :company_webhooks
end