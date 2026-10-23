const {defineConfig}=require('@playwright/test');
module.exports=defineConfig({
  testDir:'.',testMatch:'*.spec.cjs',timeout:30000,workers:1,
  use:{baseURL:'https://127.0.0.1:8765',ignoreHTTPSErrors:true,trace:'retain-on-failure',
    launchOptions:{args:['--enable-unsafe-swiftshader'],...(process.env.CHROMIUM_EXECUTABLE?{executablePath:process.env.CHROMIUM_EXECUTABLE}:{})}},
  reporter:[['list'],['json',{outputFile:'test-results/results.json'}]],
  webServer:{command:`${process.env.PYTHON || 'python3'} server.py`,url:'https://127.0.0.1:8765/admin/login',ignoreHTTPSErrors:true,
    timeout:60000,env:{PYTHONPATH:'../../',NOWAVE_TEST_ADMIN_URL:process.env.NOWAVE_TEST_ADMIN_URL}},
  projects:[{name:'desktop',use:{viewport:{width:1440,height:1000}}},{name:'mobile',use:{viewport:{width:390,height:844},hasTouch:true,isMobile:true}}]
});
