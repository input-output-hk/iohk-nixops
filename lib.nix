# To interact with this file:
# nix-repl lib.nix

let
  hostPkgs = import <nixpkgs> {};
  lib = hostPkgs.lib;
in lib // (rec {
  # TODO: sanity check there's no duplicate nodes for same index
  # https://github.com/NixOS/nixops/blob/e2015bbfcbcf7594824755e39f838d7aab258b6e/nix/eval-machine-info.nix#L173
  mergeAttrs = nodes: lib.foldAttrs (a: b: a) [] nodes;

  cardanoByName= x: nodes: let xs = builtins.filter (n: n.config.services.cardano-node.enable == true
                                     && n.config.services.cardano-node.nodeName == x) nodes;
                           in if xs != [] then (builtins.elemAt xs 0).config.services.cardano-node
                              else throw "nodeById: no node with name '${toString x}'";
  nodeCardano  = n: if !(builtins.hasAttr "cardano-node" n.config.services)
                    then throw "nodeAttr: node has no 'cardano-node' service configured."
                    else n.config.services.cardano-node;
  cardanoAttr  = a: c:
                    if !builtins.hasAttr a c || c."${a}" == null
                    then throw "nodeAttr: cardano node has no attribute '${a}'."
                    else c."${a}";

  mkNodesUsing = constructor: nodes: lib.mapAttrs  (name: nodeParams: constructor nodeParams) nodes;
  mkNodeIPs = nodes: accessKeyId: lib.mapAttrs' (name: value:
      { name = "nodeip${toString value.i}";
        value = { inherit (value) region; inherit accessKeyId;};
      }
    ) nodes;

  # fetch nixpkgs and give the expected hash
  fetchNixpkgsWithNixpkgs = nixpkgs: nixpkgs.fetchFromGitHub (builtins.fromJSON (builtins.readFile ./nixpkgs-src.json));
  fetchNixPkgs = if builtins.getEnv "NIX_PATH_LOCKED" == "1"
    then builtins.trace "using host nixpkgs" <nixpkgs>
    else builtins.trace "fetching nixpkgs"   fetchNixpkgsWithNixpkgs hostPkgs;

  traceF   = f: x: builtins.trace                         (f x)  x;
  traceSF  = f: x: builtins.trace (builtins.seq     (f x) (f x)) x;
  traceDSF = f: x: builtins.trace (builtins.deepSeq (f x) (f x)) x;

  # Parse peers from a file
  #
  # > peersFromFile ./peers.txt
  # ["ip:port/dht" "ip:port/dht" ...]
  peersFromFile = file: lib.splitString "\n" (builtins.readFile file);

  # Given a list of NixOS configs, generate a list of peers (ip/dht mappings)
  genPeersFromConfig = configs:
    let
      f = c: "${c.networking.publicIPv4}:${toString c.services.cardano-node.port}";
    in map f configs;

  # modulo operator
  # mod 11 10 == 1
  # mod 1 10 == 1
  mod = base: int: base - (int * (builtins.div base int));

  cconf = import ./config.nix;

  # Function to generate DHT key
  genDhtKey = i: (builtins.fromJSON (builtins.readFile ./static/dht.json))."node${toString i}";

  region = "eu-central-1";

  # Given a region, returns it's keypair
  # TODO: meaningful error if keypair for region doesn't exist
  keypairFor = accessKeyId: region: lib.head (lib.attrNames (lib.filterAttrs (n: v: v.region == region) (ec2KeyPairs accessKeyId)));

  ec2KeyPairs = accessKeyId: {
    cardano-test-eu-central = { inherit accessKeyId; region = "eu-central-1"; };
    cardano-test-eu-west-1 = { inherit accessKeyId; region = "eu-west-1"; };
    cardano-test-eu-west-2 = { inherit accessKeyId; region = "eu-west-2"; };
    cardano-test-ap-southeast-1 = { inherit accessKeyId; region = "ap-southeast-1"; };
    cardano-test-ap-southeast-2 = { inherit accessKeyId; region = "ap-southeast-2"; };
    cardano-test-ap-northeast-1 = { inherit accessKeyId; region = "ap-northeast-1"; };
    cardano-test-ap-northeast-2 = { inherit accessKeyId; region = "ap-northeast-2"; };
  };

  volhovmKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRMQ16PB/UvIEF+UIHfy66FNaBUWgviE2xuD5qoq/nXURBsHogGzv1ssdj1uaLdh7pZxmo/cRC+Y5f6dallIHHwdiKKOdRq1R/IWToMxnL/TTre+px6rxq21al9r4lvibelIU9vDn0R6OFZo+pRWyXUm33bQ4DVhwWiSls3Hw+9xRq4Pf2aWy//ey5CUTW+QkVdDIOFQG97kHDO3OdoNuaOMdeS+HBgH25bzSlcMw044T/NV9Cyi3y1eEBCoyqA9ba28GIl3vNADBdoQb5YYhBViFLaFsadzgWv5XWTpXV4Kwnq8ekmTcBkDzoTng/QOrDLsFMLo1nEMvhbFZopAfZ volhovm.cs@gmail.com";
  georgeeeKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCymYrIVeNUd9TUPc3cTdHIAatTg3qPbuTENNNHCKQyM4PPvWE+DzmyVDki07NpBk9Ivge3whklcTpRVTMXs7AFX3YIdIxpvc+XVgKhweqd8H0QZkC4/gsJNVTBuY1ZQ2Ldw/rRmbiA9lx/z3vtoI5p4oLSumP2qd5l/KwjDvj66X8K4KOofkFFEiPqBztQwt+A2Hh6XH5qeakQQm/TFeNL6SU0X0zKRdhjyzYAEa2Nt/Te1KK+Jkof7vZ2YnJ3jQFUhC/yRej4o3MPde0HoEP7L86rm9ORcSyQe4jZJ/d6qXMNFAG/7LfU+3LVJ+T584kHXBm5Jl5rOyX2MngNxLxP georgeee@georgeee-laptop";
  gromakKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDK0/mW1SZPMKqWawAthYKBMgLXxCfkzoAMdnQ3cakfFg5QWmmoV6QemtuaPAhBGcA4b10TPh3zW77zYY6ZnSq60iog15iAZxZByYVqBN+7j7JaQHS/cW3uf8KuVc4c/nYDrf3rj8+K0bkllKsfAM3z1JGFvYbO6UPdsjalGwG6GEvkVbbP4y+g5XG58ylgXMdUxvjWBZZTL0Ao8gc5fSeAIjkvVCM/a5EBG1/q7xTukWF2HXqQWc5/551bwDZIkUWsyUm/lr+EUFQBuwXEQ6uwhqA0MFo1r+8ge0eWB0l+fDMn59eBTBlzUNEMjafqOETJZhRU9ieDJUHEsjYVcBd7 gie1994@gmail.com";
  gromak2Key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGnZl2LJQHn7Bo1M+xKnNJPHAqjYWLhF4VBVMwqhImpacwyuMa45zmAngZz4Gb2NELflkSwSjo6Ysz7fQ7/pqe6i4N/R2W7CBHjwGYTtNtIIwSQa69sxm/KxF771+7L8XQ2NkON/njEOjAO4Bc7Z7JvGiP1EBRLeYtkgTe/MIBJ3qvBsHYMS87tyGZ3/OmRUm6JGR3PaDLFiBBMVh2JLv4rzCYWA3XTX9ZFHhlNeGuz6B/UU41UEHWvJWKJPxnZ8a0H4jqijsIM4lRL/19PA43TwybTtNOQ6TBjwZvR2dmajwfJ3ukA66Og/m9wiKSL61KBgSiSJExZn0wXAVIlg1x gromak@ivans-mbp";
  flyingleafeKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsDciZLdWUQ0elPzeJukUZLPAp/uSepUTNPo1vsK5ow4rf3XMLbHwZmIaw0M9PfSHemHHt9Fp1fzch3spm3zltOGO6bDE8Oy1UyOSV+1mGcvj2z4MuJby7tub69k6DwnlSaSDl6LgREXIAtdRbHI3+mqZWXmQp2kCPtq9Pkzv71+jZVQej/eYsO6tJF20jyP/ul9XDGmRSVizI+eaetL8CXg7tlKXNdn9/aONbzMGcmriDKdCKvxmaAYuyGBipURdmuSMwsQobfoNkvAemCpqnIdrVPjQI+s03GRmC/gecCSjWtysKu8BzlxXYJS7yNOboeZBQO2KXfDwtt6OliJuZ flyingleafe@MacBook-Air-Dmitrij.local";
  flyingleafe2Key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCZjBK3NMsPqtO6oeZU3UoDxhJjS2fqNuWkuD0CdE/wyXIHdeJ3aANgECXvl7y3hWizY48GVR7Ct2gjV9av+U+tHVMFX4ZaGl0MHl796H+4i6tkizpRKw4kuLxJ5URma6M7IBYoV/qHWgMq0FXw0/o57gRs9z4dbK1JitCdEBfLmhZiotQTb6UseQZ7Hbf8clVAtV0wZW0yjBueOtm9JpjolcZ07OoljKMZgEQ6MrHap+lPrI0X0Cxa0V5VLofl5iMKb2wSMCQ0Jd4EDi1vpwPHkHOtcbujtZXyBlUD2YXQRYgq8j2OPxr4RKzjpMxA8CbQhdnjpKWNcWV90eKg4WcxQFAtMQlJmMGmL31iU4fNWYMJXRI0LUok7QXFyPtnfYAXrmpe776Kqpa3STYRuWM3xznQIniEUU8CS+OePix4NxRPkSRoXuBcRA++i0ZV1T8jr8jn/6XzXFzCTN99RTkeXeomJWSx5Q/3EOrwQtOz4Pf0BBmtOqCKGHO/wACxJD+P1e95f7mNlmmaPcF4qUU4frUDDQPrOJiVjvxDzOCCY18Gfwt5Vwcst+0D3PyY1tW7Ai1IFTJ9TZjua40S8thg+fLORB4mpJsCrKP1YfHKRN7C7kKFq0QrJKLBcUxI69LQREFPtH0u0p1u0tNnWMWjQAjGjsuMiYPJyDmomcXjxw== flyingleafe@flf-debian";
  martoonKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCaGD+d3lU7s1Enth+sg2TZy1HKM9y+cbYSvsFGSfY1dS7J0D+emk009aJQn27PuoOS4SZI6A+Ol7d4BGL/OWZXzS9BR2a2PHmEs1xRr2EyLn7EmG/2m6UHib74gYxx4orUNkcz5rwJqoaTg/aaa2bfuADsrO6/hM0nuZvMaMj2bPVc51fQ/EwhzM8RBLmkpX6XAaB9Ghw9uvCUW+x+0BGtV+H/MlRu0kwdYFw5otO8UYQTdWULQgvarOU1Ek0SZKZORZSiVVhjo84ESiAhTFqHAozC8QimuhhaoeAnIDfPhGtg4Aen/GBqp4yCr7nF/ZoB9Jy1lXpuhO9VG6V/xC39Pck/nD1Y/V5NmMl4TWtyMEP9Ma6C/CsCSq2iBrMHQ8Uq0W2Bz9lAfQKtAaS3RnbJ0q1WdyFI6Smfiryj+DT3liP7x03W6HTkhn3yWEdtQOE6A1sfz85mIX4WUHCGAQtRz+skpW5t3MHYTmMOyThE8+l66RxQARpfpubLllCB75UjmFcc5ni+Y1MJIK/oDapGymHuZGuYQyIiKokrzp6vUfJhT6UcFBa4oQHWXJwXA7eThMtXkl4witsxG1rZBIsbjZZW1NUz1I6971d1a0cOyYw7jxutVgDVnGmsiQmtDdg4wy1kT5jDl2xvdzV0o5fzguS75jY0fcwIcDZ8W0eEUQ== martoon.391@gmail.com";
  domenKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7CTy+OMdA1IfR3EEuL/8c9tWZvfzzDH9cYE1Fq8eFsSfcoFKtb/0tAcUrhYmQMJDV54J7cLvltaoA4MV788uKl+rlqy17rKGji4gC94dvtB9eIH11p/WadgGORnjdiIV1Df29Zmjlm5zqNo2sZUxs0Nya2I4Dpa2tdXkw6piVgMtVrqPCM4W5uorX8CE+ecOUzPOi11lyfCwLcdg0OugXBVrNNSfnJ2/4PrLm7rcG4edbonjWa/FvMAHxN7BBU5+aGFC5okKOi5LqKskRkesxKNcIbsXHJ9TOsiqJKPwP0H2um/7evXiMVjn3/951Yz9Sc8jKoxAbeH/PcCmMOQz+8z7cJXm2LI/WIkiDUyAUdTFJj8CrdWOpZNqQ9WGiYQ6FHVOVfrHaIdyS4EOUG+XXY/dag0EBueO51i8KErrL17zagkeCqtI84yNvZ+L2hCSVM7uDi805Wi9DTr0pdWzh9jKNAcF7DqN16inklWUjtdRZn04gJ8N5hx55g2PAvMYWD21QoIruWUT1I7O9xbarQEfd2cC3yP+63AHlimo9Aqmj/9Qx3sRB7ycieQvNZEedLE9xiPOQycJzzZREVSEN1EK1xzle0Hg6I7U9L5LDD8yXkutvvppFb27dzlr5MTUnIy+reEHavyF9RSNXHTo57myffl8zo2lPjcmFkffLZQ== ielectric@kaki";
  alanKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBg0dSLJhcG3NtAHwi70UvdsQDy0EzDBmIfbPT2Bi2Aq4kicc3iy6vRduAOFgogdeXSL0ML5DD0KAyxgAo8aOVcGNLqsbfvhDwaQjqTjDS1twy7ZysmoFTKMfQT8k/Qs3GjL4ycEiibweJKvRHU2or7/3t+Owvu3yC56uADg4WpP2VThwACzJbwt39VKmEnf3fpxpXZ2s4/Y8bLpG/8XC0/PBbgSbgj7p5ksPAeJOCNSbhq8/NlGPOeoR/puVobX7HVwf/nfn/Jnsqzx4oZ8cuK9zM5GBi6VQ43awGsXXiTmSW57ql3M6lmBGuZOArSfYIY7PsUSQukqeoGA6E/t1r Alex Vieth";
  jakeKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCkmQINS+6ho3cI/Du2XDGYud23BKcvjcOD8XigxDfHxA17QUgVlgTZZL+/Gat3lSPQ/Pjs3FBv0SmENhhtVIevXCglMrUocr+mWDERjmUnWw2ZsR6RvEVbhyzwe6f89VnmVfcLBNgDZTJu/Yj4W6WY5hXLcFjQzCyXLwoCc4+5z+jSO+D5V8Ht10slngx3gKUx/Wx1G0CtTT7VI405JHZxgMc7iASREwN3dfCPxEUvn09Lb2yUEljAs+BOLCPnv9JWDnwhg6Iswzq0f4ORx7KNrT2NqBPl/4CxNWtyYYFRzRy/aD+u/dUJm3ZV+6xgTOI1jXIc5BrEHx4otwvV4+wZ jacob.mitchell@iohk.io";
  neongreenKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDhE3tLLE3oegMj+8pF+IByY3GoaAhX+3Mq4ff2CZt7Y+EODqC8pM+7qcOqBKAJB3p7Tay8NqzSHlF5lxihvxMICMgmpgFu8H6rD77MFI3W2mJjpmiiAf2jmn6k9lKoB4zHvTxuo9R0oftiZEa0Vlu/TQ9pP4+1SzlJ55zADAOI5B4SisCZk2+PzHodrxeemDJTSo4UMiZnsrKPCVC5zq1LlrWLcyCTfA6K7E/VCZVvopv8u7C4+Twl93yQWY/fLFo12ZdNJ918/0CTiyZ5j6Y4XjxMZAy/KNfr4z5b7Cn/ekVuLkD5a8ELN3tOoSBBi/RvIZtI/ZrH2Yy02nCIENyV yom@artyom.me";
  dshevchenkoKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8UtxHIGffqg76zqzAfAvO9CC9cgae66qcm4rjb26OGQzBewqN3cvh32U75d7UF6agXLr7O6RAF1L23G2vyJ+xuEK9zFXnbhCIoyOVnnwrNGNPqFLlDAcPwlBtaDjobJE2xYlOqgRFIzOfQa/43zr6yk696bVCk/9jjaJLWIhPJ9/BMTJ1KOcsaZB6GfHoDMICIAkFRb9Qgvq3rHy185nQP7v+olxuMRjhfrkAuUi8tZSN0Vz5DYKNBc9lgBeWXzdpI/pcaXMK7CW5GGdHUpC4S4GMtWwiii//NeVhiyHkbdHQo0pF+0w82fZOovBH5jLxtlY45kJ3nrk2a9eo0LuH dshevchenko@MacBook-Pro-Sevcenko.local";
  larsKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7AM6TDijvz2LlW4OVJXFFoiPwtxUg47861kZgwQbUpgWRAC1er81KZrF7532x6/+MO1WyO29ckdwaVRNL7M04JQDNsVRNhwl6H32rZqdBpxvnSZce4LeR0yasddFpkQmnqB2AxiNmECkw4gbxHgaSLv59pi6vPTKihNlaxK338MkuwtorcO3eJ1NB0Ap2Cl+oBO8E9eDuhArFdWwX4BhqVwIWSI7KNzj+jNavO2qyjfr1CsJpc3qJLQEdX0Oy3VSFykSvSDsk5uldcv4eglgBLNSq9qiZ0K2WlYM+BZOUdVV6bQUq+WQdLX5siEy+ZLwhACSZ3PxTgynRY3BWrWIVsyWClAWixGedz6BBeNZekGymnrcy7ncQ3F1+Vgjhtld9qmLjQYxR4/fKTKT0LtG3aDYmv9gnlwqbenNepiefRsbVYhrsuX4meHg3CUmAc40tYASPghqpKxY+BM0QwXDLQD0qzbhzGzRmASkxFcvmgEzfXlVASvFduqZPRUoKOTiUiV6aVlPQewY81BevT6SB76GM4XqArfExqHKb3S/5cnLO+8tzoxxnRMbI846rSZzh5mNYPp2SDCrvbAkbxWGxlrPJgyZWC/QlGaWCju4pzLzTpVxs1X461NPzUetdc15IlGq44QNSHHM8sIYd2GA2d8khmplPW5UFVPwpk0emcQ== brunjlar@gmail.com";
  philippKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDe56RW9j9Fj4r/yCXX+zjNh8qRjyC6DnnwAubTssganiRuCX2gIwSS4cdncXVIEnYY+T7PLv4rW7tooNL0qiBjBnLHTuvh6ibq/d3RpzCDbjpl377T16yh7wQ/Pj6yOb4xYof0fW3OLRKxK2wLqtKdmVAEfwGNxN6uIAThhk8g6+5xPyZFzRimRuMiV+vl0PPHDd1YHDuJEvt1LRuMILDtbEHHxFhO08haVCti0TthbkeTMrvG0nPCGCzh5Xy95w0QhbmgUmLevmVBexHsT4FAHI5M1DirHz9PwkXbxPIumcy0Z31dZ6JCexTTvtvPQllkC9k98VHVzd/Y24gGUaDV philipp@philipps-mbp.fritz.box";
  shershKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDOgln1GGTaghj8cAyRd9wPJWfwsFBgGY0axzVno7hlwEySDWQCcMtUysQ5N16k3R/Wc234ELPG03yJks1wmV8lncyuGSm3iEPf1zDPE5wvZIGHOZmC6r5iLezYEFqK6itz2I7TbNrNaoabTbIaJD5KZzuclnnM07ZbGTT8a+udidoav0lsJOnfprSG07g7WAjrbNs0Kokt1WIl7Rr0KBYr79Ys8WZlbKKJthsl8nAiE6Gj+6VZjHYf28QkaiNB+9MJHaYYfE3muCw0TXaWbKSHW8Mfmyiz8FiKH4/cYVvhNSd3rTygz3JQoVlRcEQcSuAxIhLeYemOGQO0cUYfTlLF fenx@smachine";
  fersel1Key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAha52s+EvlGYsiG2NGznf9ttGjedVpUDA7GwUSDHiJ9hdFptQHrugcmp0A2Hrx4KqCYkVNvYFGlIgGVySS6N0H5J3XeyJ2mi8HN8K/N405w0OWwAGbixJn+xl1coOrb4WmRWsxA7ptw0VQOgDFiBEd5h2HYys3ElkyEfw8IC/o1pRY4+iUaGd3xe3mN8ZZLybLta+4mxLlq39VV3Zv29c0FtcHW1kfLHYc2Ok2OOWK3OFhVotRiZVtiuKhDJ5rP9yCnPSXyjqe3RZ3oGDxALDdTaXp21rqxiNmDwMu4/3u4AVj+cjZftovqbk3pXKpUaXUCWzRchzrJXwvkUM9P6kTQ== rsa-key-20170404";
  fersel2Key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAiFnGf5zKfX/YHtrug4D+yz0o2RqJGzTLUq+zRGW0hf4fcJT1V6GDhnzjjgLK0r8OCBesblRsf6NO+PuVRnlx03EwomlD4HNAKyw7o0vMg9J6IaBQIESmOqDxCl8eYDMylnMCpIt+/ZKP4AneFu+8NeXxnB5Hy2gGRhkhc2MS/jkfqHdtc4V+FB1gWO4gDu+PB0kVyvsHS66J72OIiPHfPzYAfc8ZMsjssftCm3e0KEEaI3OAzIMuZTkPwX6ZFBoZP/WwRez4i0fHRbpwWm543K31gbITHCIJYlTi0T6ICPVG2j9Pz187C2BQvxwLkof4nyQdcLJypQlmMXKtuiyYiw== rsa-key-20170404";
  niklasFPCKey = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAtwCIGPYJlD2eeUtxngmT+4yR7BMlK0F5kzj+84uHsxxsy+PXFrP/tScCpwmuoiEYNv/9WKnPJJfCA9XlIDr6cla1MLpaW6eg672TRYMmKzH6SLlkg+kyDmPxSIJw+KdKfnPYyva+Y/VocACYJo0voabUeLAVgtSKGz/AFzccjfOR0GmFO911zjAaR+jFb9M7t7dveNVKm9KbuBfu3giMgGg3/mKz1TKY8yk2ZOxpT5CllBb+B5BcEf+7IGNvNxr1Z0zz5cFXQ3LyBIZklnC/OaQCnD78BSiyPTkIXcmBFal2TaFwTDvki6PuCRpJy+dU1fDdgWLql97D0SVnjmmomw== niklas";
  kosergeKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDDwRtXm1TviRRjstPHV6G+to0P7lhN5F4Za5fMxva9MbY3XequPBBU5/HjoyZUTcZYN7bVlh9TFLQW6GrwYtL8g6W7+qj9vjZAT+pdrnpLgN+mGXppzsIbe8SZdLj11+nrL+jr1EBDnu4CmIeGfGCeKmQdYcXHBxDOYUxl80Qqjw4SKzLCWa0NAiJPaO+O1BQ1gjjDSTGumTq/DFtYi0yCjhhgXRKLQFZeOc4eV3uUXzqqwKb8i89sUFNIxPnZgEpMC5IX33r8+9CcibhDvFXxhCbEhwyxAlygzJCdntwRzIigOHxBiZV+KW9nRy/sUUC/82zB6BHZPdYV9Gb3r2740BR5jTac9Qps7MkaGuFANDkjy4ASC9DiL3TGoWjiScF100kbHsBDnEqzsybQrDXxpgTd8PiqZq9I1l1as2UoeuR3IPHO7zBbgbCy4rv9a7ZeITsPT7HcRDGHsVT762KnxVxQnR3m0CpoKGKWOKngMVRCTYsQ7Ng7f/ade9isduccrMeeTjGdkeC8QGS4VnfIEEqfHPJBS8/nree40vpvtWsvKHM346GQRm6A2UI14yBZIr/SoLQEZZP3TGwcOAA4Ze3BNGjPT38gnrPO3M8HiUJCyK3RS8GMOVr2K35aS+YTKOkLRYt4vM+vwSIWLtNgjq5kXh3HHOwFAWFn2m+ZBw== koserge-2017-04";
  ksaric = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsXWw3gV6QSH19yE/wNSie+e9lcJ01kfSacEUtqkLJpV5DrhaPJ6P73c8olV3AkysmJdaMMPzaf34Q62suo0baHQPxjvZL9dXcEKPeO98EUtU6cDUclIVRQKD2zit/6hNy1EeHpaRufjzuJCoWWDhp0n17TSNcWx05UOi5W3ZWmRw4hzQLj0fJ4+DS4iNhWKGei4SeUI1XkOg7o1Rg3ODdg5hpzQx9AWy7RfO8MJoXqdjEwbhIE+rzfiXiuClCBH+uNvtNNqEp0gqtsOU3qSyn65OLVA1M3pDHQGe+xQQnJYHRVLAKFWK9Ft6YKnJZLczmgZJ85PRydLbtWPzo34ax ksaric@ksaric-H61M-S2V-B3";
  sectore = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC6DwuVqK+5Rt5iFuqSU9DhwmpklGZI+OE2/4gnfesr7kZcNIBErg+MvlOyjSHZufQrgXcjGcUbp7uP26rUVy74on8cffD9nGtPNs9t+xiCTAuCg4ddAvdszzcf7sSTQt0ElCbUuXX7QhEXGuAb0u6f6YWxnivPProq+YkZZ1OWvV3yQwhDH0xv9Vi4KJL0hv+xOhcyZGDKtjvoWbptXRmtP+aHet7wFdXaw1qlaECktqkFrfjlL///EMFm0XarMCH8qVC6sa81JIbHpSgx9FR/ZkrBB0YVgb6odh8LUPIKwvXYdwrzc1MIfPp+JpjZqnYP+2IEO5f3iuxvh5JjLpNn info@websector.de";
  michaelKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDbtjKqNiaSVMBBSK4m97LXCBwhHMfJh9NBGBxDg+XYCLOHuuKw2MsHa4eMtRhnItELxhCAXZg0rdwZTlxLb6tzsVPXAVMrVniqfbG2qZpDPNElGdjkT0J5N1X1mOzmKymucJ1uHRDxTpalpg5d5wyGZgwVuXerep3nnv2xIIYcHWm5Hy/eG0pRw6XuQUeMc3xSU5ChqZPwWqhdILkYteKMgD8vxkfmYE9N/2fPgKRmujKQ5SA0HoJYKBXo29zGQY5r6nt3CzuIANFD3vG3323Znvt8dSRd1DiaZqKEDWSI43aZ9PX2whYEDyj+L/FvQa78Wn7pc8Nv2JOb7ur9io9t michael.bishop";
  narylKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDnCVTNBCSXh9ZwufDT1j5qSD8ktA6JFAUe4sWHCtmrHrAhnUJWOalvWBnqk326k0VkiolntKRCmwUMtaBP4l8QLmthRvmV+ErD1so/xIEVF7ar5Xv/DH3T0uYrz6Im4Tbsd7506SyM+hSRwPuRb26f+LTa1c4KtuD9boNbYG1Vtu2qF1yFRjUpjXnacKkhYOlh1WA51TtTWQ++Z4a7I97kkeacmFyd4c1QLgME7DzfSyCId2IgsfgCIZtYkdK1wziJm/AWXkno+cibkvfPbnwzzK/TYtYk3xv6S/DmfN2rq5dF9rDYCOoXw7/020FGbRERVk4DvrkcIqN8JNxUJj3Z naryl@georgeee-laptop";
  pva701Key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8YZ0rSS3vRPM5ZevUld8HiVjLFFcncf8S0iwQv2vAnGVOVImugx4XbUHXj1wedvVw95/ChlYZhpc63UPA9L5i6sg00Pq+wMSpyZOTIxxKpy+HnIepjLGHQwliMcIqVKMm2rv3huCz7vwJPEjvzxoSUj0QDyTTQnmFNxpjndqYggFGHYM9Q/QtXjukJ+BJo92Tnn7o2e+XSkMZMB+6bMILr9dJC7puw63/bWu7vBwfxSw8n2WOrvVufYCn15RhRNof/j9dcIlARYgHvdtYLt14e78J3Flkb2pn8Hao4QT1gGbvZpn5wDQM7pDjrdv2N9FDbUTXaNYCXaYjjMyWeZE7 pva701@notebook";
  akegaljKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCn11qMrU3M+k/S5ScA8C37pPB7XNxzOmBnF89NkjJ16JhZxlX5tqEfq2Arja+nEG6UB8Js/5MsWTRkVYK6pB+ju0RAb5qyYomU/zZBhf9yOLlWuXTCV1ptdwRxLptjRdJ9a9YC0q715ZnNoIhfbVoR8o/CYLBFKFdFcV8O87R6mWPJ1I2CgTtfW3zjlFD8xRXtirio5EzNaq/Tq4ClQdpAOlfwHErxfk/TQMFY7vLiBdd26YEn+zD95xF4EX9cT7A2BHFD3U7OioTOTiyRwhaP3dFPcy+51fKGvxhBXtdb0fu+OanjQjsezmnBXwzSprKJUj6VjFoB4yt5qHqj0ntx akegalj@gmail.com";

  devKeys = [ volhovmKey georgeeeKey gromakKey gromak2Key flyingleafeKey flyingleafe2Key martoonKey domenKey alanKey jakeKey neongreenKey dshevchenkoKey larsKey philippKey shershKey fersel1Key fersel2Key niklasFPCKey kosergeKey ksaric sectore michaelKey narylKey pva701Key akegaljKey ];

  devOpsKeys = [ domenKey georgeeeKey jakeKey kosergeKey michaelKey ];
})
